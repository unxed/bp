{ SPDX-License-Identifier: MIT }
{ bpvet rules against casts that the compiler does not check (safe/SPEC.md §24.6, the holes H17 and H18 of §8). They
  run in the typed mode on a module that resolved (bpvettyped.pas):
    S24  an unchecked class cast: TB(O), where the static type of O is a class and TB is not one of its ancestors,
         is written O as TB (--fix does it); an upcast and a cast to the same class are free and stay;
    S25  an untyped parameter (var X, const X, out X) is unsafe, and so is a typecast of one (TBig(X)[N]) and the
         directive absolute, unless marked // UNSAFE: <why>.
  A // UNSAFE-UNIT: module is not checked. }
unit BpvetCast;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, PasTree, PasResolveEval, PasResolver, BpvetCore, Safe;

var
  { --fix: S24 writes `as` into the file (after S17 has written its marks) }
  CastFix: Boolean = False;

procedure VetCheckCasts(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);

implementation

type
  TLinesBox = specialize TOwned<TStringList>;
  TListBox = specialize TOwned<TFPList>;
  TInts = array of Integer;

  { A typecast T(X) of the checked file. Nth counts the casts of the same type name on the same line, from the left. }
  TCastSite = record
    Row: Integer;
    Name: String;
    Nth: Integer;
    Fix: Boolean;       // an S24 finding that --fix may write as `as`
    Msg: String;
    At: TPasElement;    // borrow: the cast, alive during the check
  end;

  TCast = class
  private
    FSrc: TVetSource;
    FResolver: TPasResolver;   // borrow: the resolver of the checked module, alive during the check
    FModule: TPasModule;       // borrow: the checked module
    FReport: TVetReport;
    FLines: TLinesBox;         // name=file for the sources of include files
    FSeen: TLinesBox;
    FNodes: TListBox;          // the elements of the block being checked
    FSites: array of TCastSite;
    procedure Collect(El: TPasElement; Arg: Pointer);
    function Ref(const E: TPasElement): TPasElement;
    function TypeOf(const E: TPasElement): TPasType;
    function LineOf(const FileName: String; const Row: Integer): String;
    function Marked(const El: TPasElement; const Mark: String): Boolean;
    function InMainFile(const El: TPasElement): Boolean;
    procedure Add(const El, Also: TPasElement; const Rule, Msg: String);
    function Relation(const To_, From: TPasClassType): Integer;
    procedure CheckCast(const E: TParamsExpr);
    procedure CheckArgs(const Args: TFPList; const Where: TPasElement);
    procedure CheckProc(const P: TPasProcedure);
    procedure CheckBlock(const Block: TPasImplBlock);
    procedure Walk(const Decls: TPasDeclarations);
    procedure WalkMembers(const Members: TFPList);
    procedure ApplyFixes;
  public
    constructor Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
    procedure Run;
    property Report: TVetReport read FReport;
  end;

  TCastBox = specialize TOwned<TCast>;

const
  { Relation: how a class cast goes in the hierarchy }
  RelSame = 0;      // the same class or an upcast: free
  RelDown = 1;      // a downcast: unchecked
  RelOther = 2;     // classes of different branches: the cast is wrong
  RelUnknown = 3;   // a chain of ancestors that does not resolve: no verdict

function NameOf(const El: TPasElement): String;
begin
  if (El is TBinaryExpr) and (TBinaryExpr(El).OpCode = eopSubIdent) then
    Result := NameOf(TBinaryExpr(El).right)
  else if El is TParamsExpr then
    Result := NameOf(TParamsExpr(El).Value)
  else if El is TPrimitiveExpr then
    Result := TPrimitiveExpr(El).Value
  else
    Result := El.Name;
end;

{ ---------- text of a line ---------- }

function IsIdent(const C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

{ The positions in Line, outside strings and comments, where Name stands as a whole word and an opening parenthesis
  follows (blanks may be between); a qualifier `Unit.` in front belongs to the cast. Start: the first character of the
  cast, Open: the parenthesis. }
procedure FindCasts(const Line, Name: String; var Start, Open: TInts);
var
  I, J, N: Integer;
  InStr, InBrace: Boolean;
begin
  Start := nil;
  Open := nil;
  InStr := False;
  InBrace := False;
  I := 1;
  N := Length(Line);
  while I <= N do
  begin
    if InStr then
    begin
      if Line[I] = '''' then
        InStr := False;
    end
    else if InBrace then
    begin
      if Line[I] = '}' then
        InBrace := False;
    end
    else if Line[I] = '''' then
      InStr := True
    else if Line[I] = '{' then
      InBrace := True
    else if (Line[I] = '/') and (I < N) and (Line[I + 1] = '/') then
      Break
    else if (Line[I] = '(') and (I < N) and (Line[I + 1] = '*') then
    begin
      J := Pos('*)', Line, I + 2);
      if J = 0 then
        Break;
      I := J + 1;
    end
    else if (not IsIdent(Line[I]) or (I = 1)) or (not IsIdent(Line[I - 1])) then
    begin
      if SameText(Copy(Line, I, Length(Name)), Name) and ((I + Length(Name) > N) or not IsIdent(Line[I + Length(Name)]))
        and ((I = 1) or not IsIdent(Line[I - 1])) then
      begin
        J := I + Length(Name);
        while (J <= N) and (Line[J] = ' ') do
          Inc(J);
        if (J <= N) and (Line[J] = '(') then
        begin
          SetLength(Start, Length(Start) + 1);
          SetLength(Open, Length(Open) + 1);
          Start[High(Start)] := I;
          Open[High(Open)] := J;
        end;
        I := I + Length(Name) - 1;
      end;
    end;
    Inc(I);
  end;
end;

{ The text between the parenthesis at Open and its partner, on this line; Close is the position of the partner, 0 when
  the line ends first. }
function ArgText(const Line: String; const Open: Integer; out Close: Integer): String;
var
  I, Depth: Integer;
  InStr: Boolean;
begin
  Close := 0;
  Depth := 0;
  InStr := False;
  for I := Open to Length(Line) do
  begin
    if InStr then
    begin
      if Line[I] = '''' then
        InStr := False;
      Continue;
    end;
    case Line[I] of
      '''': InStr := True;
      '(', '[': Inc(Depth);
      ')', ']':
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            Close := I;
            Exit(Trim(Copy(Line, Open + 1, I - Open - 1)));
          end;
        end;
    end;
  end;
  Result := '';
end;

{ The text has a blank outside parentheses, brackets and strings: as the left operand of `as` it needs its own
  parentheses. }
function NeedsParens(const S: String): Boolean;
var
  I, Depth: Integer;
  InStr: Boolean;
begin
  Depth := 0;
  InStr := False;
  for I := 1 to Length(S) do
  begin
    if InStr then
    begin
      if S[I] = '''' then
        InStr := False;
      Continue;
    end;
    case S[I] of
      '''': InStr := True;
      '(', '[': Inc(Depth);
      ')', ']': Dec(Depth);
      ' ': if Depth = 0 then
             Exit(True);
    end;
  end;
  Result := False;
end;

{ ---------- TCast ---------- }

constructor TCast.Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
begin
  inherited Create;
  FSrc := ASrc;
  // borrow: the resolver outlives the check (VetResolve)
  FResolver := AResolver;
  // borrow: the module outlives the check (VetResolve)
  FModule := AModule;
  FLines := TLinesBox.Own(TStringList.Create);
  FLines.Get.OwnsObjects := True;
  FSeen := TLinesBox.Own(TStringList.Create);
  FSeen.Get.Sorted := True;
  FNodes := TListBox.Own(TFPList.Create);
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure TCast.Collect(El: TPasElement; Arg: Pointer);
begin
  FNodes.Get.Add(El);
end;

function TCast.Ref(const E: TPasElement): TPasElement;
begin
  Result := nil;
  if (E <> nil) and (E.CustomData is TResolvedReference) then
    Result := TResolvedReference(E.CustomData).Declaration;
end;

function TCast.TypeOf(const E: TPasElement): TPasType;
var
  R: TPasResolverResult;
begin
  Result := nil;
  if E = nil then
    Exit;
  try
    FResolver.ComputeElement(E, R, []);
    Result := R.LoTypeEl;
  except
    on Exception do
      Result := nil;
  end;
end;

function TCast.LineOf(const FileName: String; const Row: Integer): String;
var
  I: Integer;
  L: TStringList;
begin
  if (FileName = '') or SameFileName(ExpandFileName(FileName), ExpandFileName(FSrc.FileName)) then
    Exit(VetLine(FSrc, Row));
  I := FLines.Get.IndexOfName(FileName);
  if I < 0 then
  begin
    // UNSAFE: the list FLines owns the loaded source (OwnsObjects)
    L := TStringList.Create;
    try
      L.LoadFromFile(FileName);
    except
      L.Clear;
    end;
    I := FLines.Get.AddObject(FileName + '=', L);
  end;
  L := TStringList(FLines.Get.Objects[I]);
  if (Row >= 1) and (Row <= L.Count) then
    Result := L[Row - 1]
  else
    Result := '';
end;

{ The mark is at the end of the line of El or on a comment line right above it (more comment lines may follow). }
function TCast.Marked(const El: TPasElement; const Mark: String): Boolean;
var
  Row: Integer;
  Line: String;
begin
  Row := El.SourceLinenumber;
  if Pos(Mark, LineOf(El.SourceFilename, Row)) > 0 then
    Exit(True);
  Dec(Row);
  while Row >= 1 do
  begin
    Line := TrimLeft(LineOf(El.SourceFilename, Row));
    if Copy(Line, 1, 2) <> '//' then
      Break;
    if Pos(Mark, Line) = 1 then
      Exit(True);
    Dec(Row);
  end;
  Result := False;
end;

function TCast.InMainFile(const El: TPasElement): Boolean;
begin
  Result := (El.SourceFilename = '')
    or SameFileName(ExpandFileName(El.SourceFilename), ExpandFileName(FSrc.FileName));
end;

{ A finding at El, unless a // UNSAFE: mark is at El or at Also (the routine of a parameter). }
procedure TCast.Add(const El, Also: TPasElement; const Rule, Msg: String);
var
  Row: Integer;
  Seen, Line, FileName: String;
begin
  if Marked(El, '// UNSAFE:') or ((Also <> nil) and Marked(Also, '// UNSAFE:')) then
    Exit;
  Row := El.SourceLinenumber;
  Seen := Format('%s %.6d %s %s', [El.SourceFilename, Row, Rule, Msg]);
  if FSeen.Get.IndexOf(Seen) >= 0 then
    Exit;
  FSeen.Get.Add(Seen);
  // an element of an include file is reported in that file
  FileName := FSrc.FileName;
  if not InMainFile(El) then
    FileName := El.SourceFilename;
  Line := LineOf(El.SourceFilename, Row);
  VetAdd(FReport, FileName, Row, VetWordColumn(Line, NameOf(El)), vsError, Rule, Msg);
end;

{ How a cast of a value of class From to class To_ goes: the same class or an upcast (To_ is From or an ancestor of it),
  a downcast (From is an ancestor of To_), or neither. A class without a written ancestor descends from TObject. }
function TCast.Relation(const To_, From: TPasClassType): Integer;
var
  X: TPasType;
  Depth, Up, Down: Integer;

  function Same(const A, B: TPasType): Boolean;
  begin
    Result := (A = B) or (SameText(A.Name, B.Name) and (A is TPasClassType) and (B is TPasClassType)
      and (TPasClassType(A).IsForward or TPasClassType(B).IsForward));
  end;

  { Chain: 1 when A is B or descends from it, 0 when the chain of A ends without B, -1 when it does not resolve }
  function Chain(const A, B: TPasClassType): Integer;
  begin
    X := A;
    Depth := 0;
    while (X is TPasClassType) and (Depth < 64) do
    begin
      if Same(X, B) then
        Exit(1);
      if TPasClassType(X).AncestorType = nil then
      begin
        if SameText(B.Name, 'TObject') and (TPasClassType(X).ObjKind = okClass) then
          Exit(1);
        Exit(0);
      end;
      X := TypeOf(TPasClassType(X).AncestorType);
      Inc(Depth);
    end;
    Result := -1;
  end;

begin
  Up := Chain(From, To_);
  if Up = 1 then
    Exit(RelSame);
  Down := Chain(To_, From);
  if Down = 1 then
    Exit(RelDown);
  if (Up = 0) and (Down = 0) then
    Exit(RelOther);
  Result := RelUnknown;
end;

{ S24 and S25 on a typecast T(X): a node that is a function-call syntax whose callee is a type. }
procedure TCast.CheckCast(const E: TParamsExpr);
var
  C: TPasExpr;
  D: TPasElement;
  T, ST: TPasType;
  A: TPasElement;
  Rel, K, N: Integer;
  What, Msg: String;
  Fixable: Boolean;
begin
  if Length(E.Params) <> 1 then
    Exit;
  C := E.Value;
  if (C is TBinaryExpr) and (TBinaryExpr(C).OpCode = eopSubIdent) then
    C := TBinaryExpr(C).right;
  D := Ref(C);
  if not (D is TPasType) then
    Exit;
  What := NameOf(E);
  // S25: a typecast of an untyped parameter
  A := Ref(E.Params[0]);
  if (A is TPasArgument) and (TPasArgument(A).ArgType = nil) then
    Add(E, nil, 'S25', Format('%s(%s) casts an untyped parameter: whatever the caller passed is read as a %s; give %s '
      + 'its type, or mark the cast // UNSAFE: <why>', [What, A.Name, What, A.Name]));
  // S24: a class cast
  T := TypeOf(C);
  if not ((T is TPasClassType) and (TPasClassType(T).ObjKind = okClass)) then
    Exit;
  ST := TypeOf(E.Params[0]);
  if not ((ST is TPasClassType) and (TPasClassType(ST).ObjKind = okClass)) then
    Exit;
  // the site counts for the fix, which pairs the casts of the tree with those of the text
  N := 1;
  for K := 0 to High(FSites) do
    if (FSites[K].Row = E.SourceLinenumber) and SameText(FSites[K].Name, What) then
      Inc(N);
  K := Length(FSites);
  SetLength(FSites, K + 1);
  FSites[K].Row := E.SourceLinenumber;
  FSites[K].Name := What;
  FSites[K].Nth := N;
  FSites[K].Fix := False;
  FSites[K].Msg := '';
  FSites[K].At := E;
  if not InMainFile(E) then
    FSites[K].Row := -1;
  Rel := Relation(TPasClassType(T), TPasClassType(ST));
  if (Rel = RelSame) or (Rel = RelUnknown) or Marked(E, '// UNSAFE:') then
    Exit;
  Fixable := Rel = RelDown;
  if Rel = RelDown then
    Msg := Format('the cast %s(...) of a %s to its descendant %s is not checked: a wrong class is read as %s without '
      + 'an error; write `... as %s`, which raises EInvalidCast (bpvet --fix writes it), or mark it // UNSAFE: <why>',
      [What, ST.Name, T.Name, T.Name, What])
  else
  begin
    Msg := Format('the cast %s(...) of a %s: the classes are of different branches, so the object is never a %s; '
      + 'remove the cast or mark it // UNSAFE: <why>', [What, ST.Name, T.Name]);
  end;
  FSites[K].Fix := Fixable;
  FSites[K].Msg := Msg;
end;

{ S25: the untyped parameters among Args. Where: the routine or procedure type that declares them (a mark above it
  holds for all). }
procedure TCast.CheckArgs(const Args: TFPList; const Where: TPasElement);
var
  I: Integer;
  A: TPasArgument;
begin
  for I := 0 to Args.Count - 1 do
  begin
    A := TPasArgument(Args[I]);
    if (A.ArgType = nil) and (A.Access in [argVar, argConst, argOut]) then
      Add(A, Where, 'S25', Format('the untyped parameter %s takes any variable and hands out no check of its size '
        + 'or type: give it a type, a generic or an open array, or mark it // UNSAFE: <why>', [A.Name]));
  end;
end;

procedure TCast.CheckProc(const P: TPasProcedure);
var
  D: TPasProcedure;
begin
  if P.ProcType = nil then
    Exit;
  // an implementation is checked at its declaration
  if (P.CustomData is TPasProcedureScope) then
  begin
    D := TPasProcedureScope(P.CustomData).DeclarationProc;
    if (D <> nil) and (D <> P) then
      Exit;
  end;
  CheckArgs(P.ProcType.Args, P);
end;

procedure TCast.CheckBlock(const Block: TPasImplBlock);
var
  I: Integer;
  N: TPasElement;
begin
  if Block = nil then
    Exit;
  FNodes.Get.Clear;
  Block.ForEachCall(@Collect, nil);
  for I := 0 to FNodes.Get.Count - 1 do
  begin
    N := TPasElement(FNodes.Get[I]);
    if (N is TParamsExpr) and (TParamsExpr(N).Kind = pekFuncParams) then
      CheckCast(TParamsExpr(N));
  end;
end;

procedure TCast.WalkMembers(const Members: TFPList);
var
  I: Integer;
  M: TPasElement;
begin
  for I := 0 to Members.Count - 1 do
  begin
    M := TPasElement(Members[I]);
    if M is TPasProcedure then
      CheckProc(TPasProcedure(M))
    else if M is TPasClassType then
      WalkMembers(TPasClassType(M).Members)
    else if M is TPasRecordType then
      WalkMembers(TPasRecordType(M).Members);
  end;
end;

procedure TCast.Walk(const Decls: TPasDeclarations);
var
  I: Integer;
  D: TPasElement;
begin
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    D := TPasElement(Decls.Declarations[I]);
    if D is TPasProcedure then
    begin
      CheckProc(TPasProcedure(D));
      if TPasProcedure(D).Body <> nil then
      begin
        CheckBlock(TPasProcedure(D).Body.Body);
        Walk(TPasProcedure(D).Body);
      end;
    end
    else if D is TPasClassType then
      WalkMembers(TPasClassType(D).Members)
    else if D is TPasRecordType then
      WalkMembers(TPasRecordType(D).Members)
    else if D is TPasProcedureType then
      CheckArgs(TPasProcedureType(D).Args, D)
    else if (D is TPasVariable) and not (D is TPasConst) and not (D is TPasProperty)
      and (TPasVariable(D).AbsoluteExpr <> nil) then
      Add(D, nil, 'S25', Format('%s is declared absolute: it is the memory of another variable under a type of its '
        + 'own; use a typecast of the right kind or mark it // UNSAFE: <why>', [D.Name]));
  end;
end;

{ Writes `as` for the downcasts that can be found in the text: the n-th cast T( on the line of the tree is the n-th
  T( of the text (strings and comments are left out); a line where the two counts differ is left to the finding. The
  file is read again, since S17 has written its marks into it. }
procedure TCast.ApplyFixes;
var
  Lines: TLinesBox;
  I, K, Total, Close, At, Open: Integer;
  Starts, Opens: TInts;
  Line, Inner, Name, Head: String;
  Written, Tried: array of Boolean;
  Any: Boolean;
begin
  Any := False;
  for I := 0 to High(FSites) do
    Any := Any or FSites[I].Fix;
  if not Any then
    Exit;
  SetLength(Written, Length(FSites));
  SetLength(Tried, Length(FSites));
  Lines := TLinesBox.Own(TStringList.Create);
  try
    Lines.Get.LoadFromFile(FSrc.FileName);
  except
    on Exception do
      Exit;
  end;
  for I := 0 to High(FSites) do
  begin
    if not FSites[I].Fix or Tried[I] or (FSites[I].Row < 1) or (FSites[I].Row > Lines.Get.Count) then
      Continue;
    Name := FSites[I].Name;
    Total := 0;
    for K := 0 to High(FSites) do
      if (FSites[K].Row = FSites[I].Row) and SameText(FSites[K].Name, Name) then
        Inc(Total);
    for K := 0 to High(FSites) do
      if (FSites[K].Row = FSites[I].Row) and SameText(FSites[K].Name, Name) then
        Tried[K] := True;
    Line := Lines.Get[FSites[I].Row - 1];
    FindCasts(Line, Name, Starts, Opens);
    if Length(Starts) <> Total then
      Continue;
    // from the right, so that the positions on the left stay valid
    for K := High(FSites) downto 0 do
    begin
      if not ((FSites[K].Row = FSites[I].Row) and SameText(FSites[K].Name, Name) and FSites[K].Fix) then
        Continue;
      At := Starts[FSites[K].Nth - 1];
      Open := Opens[FSites[K].Nth - 1];
      Inner := ArgText(Line, Open, Close);
      if (Close = 0) or (Inner = '') then
        Continue;
      Head := Trim(Copy(Line, At, Open - At));
      if NeedsParens(Inner) then
        Inner := '(' + Inner + ')';
      Line := Copy(Line, 1, At - 1) + '(' + Inner + ' as ' + Head + ')' + Copy(Line, Close + 1, Length(Line));
      Written[K] := True;
    end;
    Lines.Get[FSites[I].Row - 1] := Line;
  end;
  Lines.Get.SaveToFile(FSrc.FileName);
  // a cast written is no finding
  for I := 0 to High(FSites) do
    if Written[I] then
      FSites[I].Msg := '';
end;

procedure TCast.Run;
var
  I: Integer;
begin
  Walk(FModule.InterfaceSection);
  Walk(FModule.ImplementationSection);
  if FModule is TPasProgram then
    Walk(TPasProgram(FModule).ProgramSection);
  CheckBlock(FModule.InitializationSection);
  CheckBlock(FModule.FinalizationSection);
  if CastFix then
    ApplyFixes;
  for I := 0 to High(FSites) do
    if FSites[I].Msg <> '' then
      Add(FSites[I].At, nil, 'S24', FSites[I].Msg);
end;

procedure VetCheckCasts(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);
var
  C: TCastBox;
  I: Integer;
begin
  for I := 0 to High(Src.Lines) do
    if Pos('// UNSAFE-UNIT:', Src.Lines[I]) = 1 then
      Exit;
  C := TCastBox.Own(TCast.Create(Src, Resolver, Module));
  C.Get.Run;
  for I := 0 to High(C.Get.Report.Findings) do
    with C.Get.Report.Findings[I] do
      VetAdd(Report, FileName, Row, Col, Severity, Rule, Msg);
end;

end.
