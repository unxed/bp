{ SPDX-License-Identifier: MIT }
{ bpvet rules against data races between goroutines (safe/SPEC.md §21.2, the holes H14-H16 of §8). They run in the
  typed mode on a module that resolved (bpvettyped.pas):
    S11m  Send = move: a value that holds a dynamic array goes into a channel (Ch.Send) or into the constructor of a
          task only as Copy(X), a fresh value (an array literal, a function result) or the last use of a local;
    S11s  Sync = frozen or declared: TShared<X> in a task field or in a channel message needs X frozen (its fields are
          written only in its constructors, and their types are frozen too) or a // sync: <how> mark on X;
    S19   static mut is unsafe: a global of a unit is written only in initialization or finalization, or it is a
          threadvar, or the write is atomic (Interlocked*) or marked // UNSAFE: <why>; a global of a program is not
          named by a routine that a task reaches.
  A // UNSAFE-UNIT: module is not checked. }
unit BpvetRace;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, PasTree, PasResolveEval, PasResolver, BpvetCore, Safe;

procedure VetCheckRaces(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);

implementation

type
  TLinesBox = specialize TOwned<TStringList>;
  TListBox = specialize TOwned<TFPList>;

  TRace = class
  private
    FSrc: TVetSource;
    FResolver: TPasResolver;  // borrow: the resolver of the checked module, alive during the check
    FModule: TPasModule;      // borrow: the checked module
    FReport: TVetReport;
    FLines: TLinesBox;        // name=file for the sources of other units (// sync: marks, threadvar sections)
    FNodes: TListBox;         // the elements of the routine being checked, in the order of the source
    FNested: TListBox;        // the declarations that nested routines of that routine read
    FWrites: TLinesBox;       // class=reason: classes whose fields are written outside their constructors
    FFrozen: TLinesBox;       // class=reason ('' when frozen): the verdicts so far
    FSeen: TLinesBox;
    FProc: TPasProcedure;     // borrow: the routine being checked, nil for an initialization or main block
    FLocals: TPasDeclarations; // borrow: the declarations whose variables are locals of the block being checked
    procedure Collect(El: TPasElement; Arg: Pointer);
    procedure CollectNested(El: TPasElement; Arg: Pointer);
    function Ref(const E: TPasElement): TPasElement;
    function TypeOf(const E: TPasElement): TPasType;
    function LineOf(const FileName: String; const Row: Integer): String;
    function Marked(const El: TPasElement; const Mark: String): Boolean;
    procedure Add(const El: TPasElement; const Rule, Msg: String);
    function HoldsArray(const T: TPasType; const Depth: Integer): Boolean;
    function SharedOf(const T: TPasType): TPasType;
    function ChanElem(const T: TPasType): TPasType;
    function Frozen(const C: TPasType; const Depth: Integer): String;
    function FrozenType(const T: TPasType; const Depth: Integer): String;
    function Chain(const E: TPasExpr): TFPList;
    function OwnerClass(const P: TPasProcedure): TPasClassType;
    function IsGlobal(const D: TPasElement): Boolean;
    function IsThreadVar(const D: TPasElement): Boolean;
    function IsTaskClass(const C: TPasType): Boolean;
    function DescendsFrom(const C, A: TPasType): Boolean;
    procedure Written(const L: TPasExpr; const Site: TPasElement);
    procedure CheckMove(const Arg: TPasExpr; const Site: Integer; const What, Verb: String);
    procedure CheckShared(const Where: TPasElement; const T: TPasType; const What: String);
    procedure Scan(const Block: TPasImplBlock; const Decls: TPasDeclarations; const P: TPasProcedure;
      const Writes: Boolean);
    procedure ScanDecls(const Decls: TPasDeclarations);
    procedure CheckTypes(const Decls: TPasDeclarations);
    function ImplOf(const P: TPasProcedure): TPasProcedure;
    function DeclOf(const P: TPasProcedure): TPasProcedure;
    function Overrides(const P, C: TPasProcedure): Boolean;
    procedure AllProcs(const Decls: TPasDeclarations; const All: TFPList);
    procedure Reach(const R: TPasProcedure; const Who: String; const Reached: TFPList; const From: TStringList;
      const All: TFPList);
    procedure GoSites(const Reached: TFPList; const From: TStringList; const All: TFPList);
    function SyncGlobal(const N: TPasElement; const D: TPasVariable): Boolean;
    procedure CheckProgramGlobals(const Prog: TPasProgram);
  public
    constructor Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
  end;

  TRaceBox = specialize TOwned<TRace>;

const
  MaxDepth = 8;
  { the records of Better Pascal that are handles or owners, not values that hold an array }
  Handles: array[0..5] of String = ('TChan', 'TShared', 'TOwned', 'TWeak', 'TGroup', 'TSafeChan');

function StartsWithName(const Name, Prefix: String): Boolean;
begin
  Result := SameText(Copy(Name, 1, Length(Prefix)), Prefix)
    and ((Length(Name) = Length(Prefix)) or (Name[Length(Prefix) + 1] in ['<', '$', '_']));
end;

function IsHandle(const T: TPasType): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Handles) do
    if StartsWithName(T.Name, Handles[I]) then
      Exit(True);
  Result := False;
end;

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

{ El is inside Outer (or is it). }
function Inside(const El, Outer: TPasElement): Boolean;
var
  P: TPasElement;
begin
  P := El;
  while P <> nil do
  begin
    if P = Outer then
      Exit(True);
    P := P.Parent;
  end;
  Result := False;
end;

{ ---------- TRace ---------- }

constructor TRace.Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
begin
  inherited Create;
  FSrc := ASrc;
  // borrow: the resolver outlives the check (VetResolve)
  FResolver := AResolver;
  // borrow: the module outlives the check (VetResolve)
  FModule := AModule;
  FLines := TLinesBox.Own(TStringList.Create);
  FLines.Get.OwnsObjects := True;
  FNodes := TListBox.Own(TFPList.Create);
  FNested := TListBox.Own(TFPList.Create);
  FWrites := TLinesBox.Own(TStringList.Create);
  FFrozen := TLinesBox.Own(TStringList.Create);
  FSeen := TLinesBox.Own(TStringList.Create);
  FSeen.Get.Sorted := True;
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure TRace.Collect(El: TPasElement; Arg: Pointer);
begin
  FNodes.Get.Add(El);
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure TRace.CollectNested(El: TPasElement; Arg: Pointer);
var
  D: TPasElement;
begin
  D := Ref(El);
  if D <> nil then
    FNested.Get.Add(D);
end;

function TRace.Ref(const E: TPasElement): TPasElement;
begin
  Result := nil;
  if (E <> nil) and (E.CustomData is TResolvedReference) then
    Result := TResolvedReference(E.CustomData).Declaration;
end;

function TRace.TypeOf(const E: TPasElement): TPasType;
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

function TRace.LineOf(const FileName: String; const Row: Integer): String;
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
function TRace.Marked(const El: TPasElement; const Mark: String): Boolean;
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

procedure TRace.Add(const El: TPasElement; const Rule, Msg: String);
var
  Row: Integer;
  Seen, Line, FileName: String;
begin
  Row := El.SourceLinenumber;
  if Marked(El, '// UNSAFE:') then
    Exit;
  Seen := Format('%s %.6d %s %s', [El.SourceFilename, Row, Rule, Msg]);
  if FSeen.Get.IndexOf(Seen) >= 0 then
    Exit;
  FSeen.Get.Add(Seen);
  // an element of an include file is reported in that file
  FileName := FSrc.FileName;
  if (El.SourceFilename <> '') and not SameFileName(ExpandFileName(El.SourceFilename), ExpandFileName(FileName)) then
    FileName := El.SourceFilename;
  Line := LineOf(El.SourceFilename, Row);
  VetAdd(FReport, FileName, Row, VetWordColumn(Line, NameOf(El)), vsError, Rule, Msg);
end;

{ T holds a dynamic array: it is one, or a record or a static array with one inside. A string does not count: a write
  to a shared string copies it first. }
function TRace.HoldsArray(const T: TPasType; const Depth: Integer): Boolean;
var
  I: Integer;
  M: TPasElement;
begin
  Result := False;
  if (T = nil) or (Depth > MaxDepth) then
    Exit;
  if T is TPasArrayType then
  begin
    if Length(TPasArrayType(T).Ranges) = 0 then
      Exit(True);
    Exit(HoldsArray(TypeOf(TPasArrayType(T).ElType), Depth + 1));
  end;
  if (T is TPasRecordType) and not IsHandle(T) then
    for I := 0 to TPasRecordType(T).Members.Count - 1 do
    begin
      M := TPasElement(TPasRecordType(T).Members[I]);
      if (M is TPasVariable) and not (M is TPasConst) and not (M is TPasProperty)
        and HoldsArray(TypeOf(TPasVariable(M).VarType), Depth + 1) then
        Exit(True);
    end;
end;

{ The class X of a TShared<X>, else nil. }
function TRace.SharedOf(const T: TPasType): TPasType;
var
  I: Integer;
  M: TPasElement;
begin
  Result := nil;
  if not ((T is TPasRecordType) and StartsWithName(T.Name, 'TShared')) then
    Exit;
  for I := 0 to TPasRecordType(T).Members.Count - 1 do
  begin
    M := TPasElement(TPasRecordType(T).Members[I]);
    if (M is TPasVariable) and SameText(M.Name, 'FObj') then
      Exit(TypeOf(TPasVariable(M).VarType));
  end;
end;

{ The message type of a TChan<T>, else nil. }
function TRace.ChanElem(const T: TPasType): TPasType;
var
  I: Integer;
  M: TPasElement;
begin
  Result := nil;
  if not ((T is TPasRecordType) and StartsWithName(T.Name, 'TChan')) then
    Exit;
  for I := 0 to TPasRecordType(T).Members.Count - 1 do
  begin
    M := TPasElement(TPasRecordType(T).Members[I]);
    if (M is TPasProcedure) and SameText(M.Name, 'Send') and (TPasProcedure(M).ProcType.Args.Count = 1) then
      Exit(TypeOf(TPasArgument(TPasProcedure(M).ProcType.Args[0]).ArgType));
  end;
end;

{ '' when a value of type T may be shared by goroutines without a lock, else why not. }
function TRace.FrozenType(const T: TPasType; const Depth: Integer): String;
var
  I: Integer;
  M: TPasElement;
  X: TPasType;
begin
  Result := '';
  if (T = nil) or (Depth > MaxDepth) then
    Exit;
  if T is TPasUnresolvedSymbolRef then
  begin
    if SameText(T.Name, 'Pointer') then
      Result := 'a Pointer';
    Exit;
  end;
  if (T is TPasEnumType) or (T is TPasSetType) or (T is TPasRangeType) then
    Exit;
  if T is TPasArrayType then
    Exit(FrozenType(TypeOf(TPasArrayType(T).ElType), Depth + 1));
  if T is TPasRecordType then
  begin
    if StartsWithName(T.Name, 'TChan') then
      Exit;
    X := SharedOf(T);
    if (X = nil) and StartsWithName(T.Name, 'TOwned') then
      for I := 0 to TPasRecordType(T).Members.Count - 1 do
        if (TObject(TPasRecordType(T).Members[I]) is TPasVariable)
          and SameText(TPasElement(TPasRecordType(T).Members[I]).Name, 'FObj') then
          X := TypeOf(TPasVariable(TPasRecordType(T).Members[I]).VarType);
    if X <> nil then
    begin
      Result := Frozen(X, Depth + 1);
      if Result <> '' then
        Result := Format('%s (%s)', [X.Name, Result]);
      Exit;
    end;
    for I := 0 to TPasRecordType(T).Members.Count - 1 do
    begin
      M := TPasElement(TPasRecordType(T).Members[I]);
      if (M is TPasVariable) and not (M is TPasConst) and not (M is TPasProperty) then
      begin
        Result := FrozenType(TypeOf(TPasVariable(M).VarType), Depth + 1);
        if Result <> '' then
          Exit;
      end;
    end;
    Exit;
  end;
  if T is TPasClassType then
  begin
    if TPasClassType(T).ObjKind = okInterface then
      Exit('the interface ' + T.Name);
    Result := Frozen(T, Depth + 1);
    if Result <> '' then
      Result := Format('%s (%s)', [T.Name, Result]);
    Exit;
  end;
  Result := 'the type ' + T.Name;
end;

{ '' when the class C is frozen (or marked // sync:), else why not (its field F is written in R, line N). }
function TRace.Frozen(const C: TPasType; const Depth: Integer): String;
var
  I, K: Integer;
  A: TPasType;
  M: TPasElement;
begin
  Result := '';
  if not (C is TPasClassType) or (Depth > MaxDepth) then
    Exit;
  K := FFrozen.Get.IndexOfName(C.Name);
  if K >= 0 then
    Exit(FFrozen.Get.ValueFromIndex[K]);
  if Marked(C, '// sync:') then
  begin
    FFrozen.Get.Add(C.Name + '=');
    Exit;
  end;
  FFrozen.Get.Add(C.Name + '=');  // a cycle through the fields is frozen as far as this class goes
  A := C;
  while (Result = '') and (A is TPasClassType) do
  begin
    if SameText(A.Name, 'TObject') or SameText(A.Name, 'TInterfacedObject') then
      Break;
    if A.GetModule <> FModule then
    begin
      Result := Format('its class %s is declared in another unit, where the writes are not seen', [A.Name]);
      Break;
    end;
    K := FWrites.Get.IndexOfName(A.Name);
    if K >= 0 then
      Result := FWrites.Get.ValueFromIndex[K];
    for I := 0 to TPasClassType(A).Members.Count - 1 do
    begin
      if Result <> '' then
        Break;
      M := TPasElement(TPasClassType(A).Members[I]);
      if (M is TPasVariable) and not (M is TPasConst) and not (M is TPasProperty) then
      begin
        Result := FrozenType(TypeOf(TPasVariable(M).VarType), Depth + 1);
        if Result <> '' then
          Result := Format('its field %s holds %s', [M.Name, Result]);
      end;
    end;
    A := TPasClassType(A).AncestorType;
    if A <> nil then
      A := TypeOf(A);
  end;
  K := FFrozen.Get.IndexOfName(C.Name);
  FFrozen.Get[K] := C.Name + '=' + Result;
end;

{ The declarations an access names, from the base: A.B[I].C gives A, B, C. The caller owns the list. }
function TRace.Chain(const E: TPasExpr): TFPList;
var
  X: TPasExpr;
  D: TPasElement;
begin
  // UNSAFE: the caller frees the list
  Result := TFPList.Create;
  X := E;
  while X <> nil do
  begin
    if (X is TBinaryExpr) and (TBinaryExpr(X).OpCode = eopSubIdent) then
    begin
      D := Ref(TBinaryExpr(X).right);
      if D <> nil then
        Result.Insert(0, D);
      X := TBinaryExpr(X).left;
    end
    else if (X is TParamsExpr) and (TParamsExpr(X).Kind = pekArrayParams) then
      X := TParamsExpr(X).Value
    else if X is TUnaryExpr then
      X := TUnaryExpr(X).Operand
    else
    begin
      D := Ref(X);
      if D <> nil then
        Result.Insert(0, D);
      X := nil;
    end;
  end;
end;

function TRace.OwnerClass(const P: TPasProcedure): TPasClassType;
var
  D: TPasProcedure;
begin
  Result := nil;
  if P = nil then
    Exit;
  D := P;
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    D := TPasProcedureScope(P.CustomData).DeclarationProc;
  if D.Parent is TPasClassType then
    Result := TPasClassType(D.Parent);
end;

{ A global variable of a unit (not of a program: those are the locals of its main goroutine). }
function TRace.IsGlobal(const D: TPasElement): Boolean;
begin
  Result := (D is TPasVariable) and not (D is TPasConst) and not (D is TPasProperty) and (D.Parent is TPasSection)
    and not (D.GetModule is TPasProgram);
end;

{ The section of D starts with threadvar: the nearest line above it that opens a section. }
function TRace.IsThreadVar(const D: TPasElement): Boolean;
var
  Row: Integer;
  W: String;
begin
  Row := D.SourceLinenumber;
  while Row >= 1 do
  begin
    W := LowerCase(Trim(LineOf(D.SourceFilename, Row)));
    if (Copy(W, 1, 9) = 'threadvar') then
      Exit(True);
    if (W = 'var') or (Copy(W, 1, 4) = 'var ') or (W = 'const') or (W = 'type') or (Copy(W, 1, 9) = 'procedure')
      or (Copy(W, 1, 8) = 'function') or (W = 'implementation') or (W = 'interface') then
      Exit(False);
    Dec(Row);
  end;
  Result := False;
end;

function TRace.DescendsFrom(const C, A: TPasType): Boolean;
var
  X: TPasType;
begin
  X := C;
  while X is TPasClassType do
  begin
    if X = A then
      Exit(True);
    X := TPasClassType(X).AncestorType;
    if X <> nil then
      X := TypeOf(X);
  end;
  Result := False;
end;

function TRace.IsTaskClass(const C: TPasType): Boolean;
var
  A: TPasType;
begin
  A := C;
  while A is TPasClassType do
  begin
    if SameText(A.Name, 'TTask') then
      Exit(True);
    A := TPasClassType(A).AncestorType;
    if A <> nil then
      A := TypeOf(A);
  end;
  Result := False;
end;

{ L is written at Site: a global of a unit (S19), a field of a class outside its constructors (for S11s). }
procedure TRace.Written(const L: TPasExpr; const Site: TPasElement);
var
  C: TFPList;
  I: Integer;
  D: TPasElement;
  Own: TPasClassType;
  F: TPasClassType;
  RoutineName: String;
begin
  if FProc = nil then
    RoutineName := 'the main block'
  else
    RoutineName := FProc.Name;
  C := Chain(L);
  try
    if C.Count = 0 then
      Exit;
    D := TPasElement(C[0]);
    if IsGlobal(D) and (FProc <> nil) and not IsThreadVar(D) then
      Add(L, 'S19', Format('the global %s is written in %s, and every goroutine sees it: write it only in the '
        + 'initialization of its unit, make it a threadvar, pass it as a parameter, or send it through a channel; '
        + 'a lock that guards it is // UNSAFE: <the lock>', [D.Name, FProc.Name]));
    Own := OwnerClass(FProc);
    for I := 0 to C.Count - 1 do
    begin
      D := TPasElement(C[I]);
      if not ((D is TPasVariable) and not (D is TPasConst) and (D.Parent is TPasClassType)) then
        Continue;
      F := TPasClassType(D.Parent);
      // a constructor or a destructor writes the fields of its class and of its ancestors while the object is built
      if ((FProc is TPasConstructor) or (FProc is TPasDestructor)) and DescendsFrom(Own, F) then
        Continue;
      if FWrites.Get.IndexOfName(F.Name) < 0 then
        FWrites.Get.Add(Format('%s=its field %s is written in %s, line %d', [F.Name, D.Name,
          RoutineName, Site.SourceLinenumber]));
    end;
  finally
    // UNSAFE: the list of Chain, freed here
    C.Destroy;
  end;
end;

{ Arg is the node at index Site of FNodes or below it; it goes into a channel or a task. }
procedure TRace.CheckMove(const Arg: TPasExpr; const Site: Integer; const What, Verb: String);
var
  D, N, Loop, P: TPasElement;
  I, Next, Wrap, After: Integer;

  function Reassigned(const Idx: Integer): Boolean;
  var
    E: TPasElement;
  begin
    if Idx < 0 then
      Exit(True);
    E := TPasElement(FNodes.Get[Idx]);
    Result := ((E.Parent is TPasImplAssign) and (TPasImplAssign(E.Parent).left = E)
      and (TPasImplAssign(E.Parent).Kind = akDefault))
      or ((E.Parent is TParamsExpr) and (TParamsExpr(E.Parent).Params[0] = E)
      and SameText(NameOf(TParamsExpr(E.Parent).Value), 'SetLength'));
  end;

begin
  if not HoldsArray(TypeOf(Arg), 0) then
    Exit;
  // a fresh value: Copy(X), an array literal, the result of a function
  if (Arg is TParamsExpr) and (TParamsExpr(Arg).Kind = pekSet) then
    Exit;
  if Arg is TArrayValues then
    Exit;
  N := Arg;
  if Arg is TParamsExpr then
    N := TParamsExpr(Arg).Value;
  if (N is TBinaryExpr) and (TBinaryExpr(N).OpCode = eopSubIdent) then
    N := TBinaryExpr(N).right;
  D := Ref(N);
  if (D is TPasFunction) or ((D is TPasUnresolvedSymbolRef) and SameText(D.Name, 'Copy'))
    or ((Arg is TParamsExpr) and (TParamsExpr(Arg).Kind = pekFuncParams) and not (D is TPasVariable)
      and not (D is TPasProperty)) then
    Exit;
  if not (Arg is TPrimitiveExpr) or (D = nil) then
  begin
    Add(Arg, 'S11m', Format('%s shares a dynamic array with the sender (an array is a reference): %s Copy(%s), '
      + 'or a local the sender does not use after this line', [What, Verb, NameOf(Arg)]));
    Exit;
  end;
  // a dynamic array passed by value is the array of the caller too: only its reference count grows
  if D is TPasArgument then
  begin
    Add(Arg, 'S11m', Format('%s shares the array of the parameter %s with the caller, who still holds it: %s '
      + 'Copy(%s)', [What, D.Name, Verb, D.Name]));
    Exit;
  end;
  if not ((D is TPasVariable) and (D.Parent = FLocals)) then
  begin
    Add(Arg, 'S11m', Format('%s shares the array of %s, which is not a local of this routine: %s Copy(%s)',
      [What, D.Name, Verb, D.Name]));
    Exit;
  end;
  if FNested.Get.IndexOf(D) >= 0 then
  begin
    Add(Arg, 'S11m', Format('%s moves the local %s, but a nested routine reads it: %s Copy(%s)', [What, D.Name,
      Verb, D.Name]));
    Exit;
  end;
  // the last use: the next read of D after the send (in a loop also the next iteration) must not exist
  Loop := nil;
  P := Arg.Parent;
  while (P <> nil) and (Loop = nil) do
  begin
    if (P is TPasImplForLoop) or (P is TPasImplWhileDo) or (P is TPasImplRepeatUntil) then
      Loop := P;
    P := P.Parent;
  end;
  Next := -1;
  Wrap := -1;
  After := -1;
  for I := 0 to FNodes.Get.Count - 1 do
  begin
    N := TPasElement(FNodes.Get[I]);
    if (N = Arg) or not (N is TPrimitiveExpr) or (Ref(N) <> D) then
      Continue;
    if (Loop <> nil) and Inside(N, Loop) then
    begin
      if (I > Site) and (Next < 0) then
        Next := I
      else if (I < Site) and (Wrap < 0) then
        Wrap := I;
    end
    else if (I > Site) and (After < 0) then
      After := I;
  end;
  if Loop = nil then
    Next := After
  else if Next < 0 then
    Next := Wrap;
  if not Reassigned(Next) or ((Loop <> nil) and not Reassigned(After)) then
    Add(Arg, 'S11m', Format('%s moves the array of %s, but %s is read again on line %d, and both sides would share '
      + 'it: %s Copy(%s), or assign %s a new array before that line', [What, D.Name, D.Name,
      TPasElement(FNodes.Get[Next]).SourceLinenumber, Verb, D.Name, D.Name]));
end;

{ T, the type of a task field or a channel message, may carry a TShared<X> (also inside a record). }
procedure TRace.CheckShared(const Where: TPasElement; const T: TPasType; const What: String);
var
  X: TPasType;
  Why: String;
  I: Integer;
  M: TPasElement;
begin
  if T = nil then
    Exit;
  X := SharedOf(T);
  if X <> nil then
  begin
    Why := Frozen(X, 0);
    if Why <> '' then
      Add(Where, 'S11s', Format('%s carries TShared<%s> to another goroutine, and %s is not frozen: %s; write the '
        + 'fields only in the constructors, or mark %s // sync: <the lock or the protocol>', [What, X.Name, X.Name,
        Why, X.Name]));
    Exit;
  end;
  if (T is TPasRecordType) and not IsHandle(T) then
    for I := 0 to TPasRecordType(T).Members.Count - 1 do
    begin
      M := TPasElement(TPasRecordType(T).Members[I]);
      if (M is TPasVariable) and not (M is TPasConst) and not (M is TPasProperty) then
        CheckShared(Where, TypeOf(TPasVariable(M).VarType), What);
    end;
end;

{ One block: the statements of a routine, an initialization or a main block. Writes: the pass that records the
  writes (S19 and the writes of fields); otherwise the pass of S11m. }
procedure TRace.Scan(const Block: TPasImplBlock; const Decls: TPasDeclarations; const P: TPasProcedure;
  const Writes: Boolean);
var
  I, J: Integer;
  N, D, C: TPasElement;
  E: TParamsExpr;
  Proc: TPasProcedure;
begin
  if Block = nil then
    Exit;
  // borrow: the routine and its declarations are part of the module, alive during the check
  FProc := P;
  // borrow: the same
  FLocals := Decls;
  FNodes.Get.Clear;
  FNested.Get.Clear;
  Block.ForEachCall(@Collect, nil);
  if Decls <> nil then
    for I := 0 to Decls.Declarations.Count - 1 do
      if (TObject(Decls.Declarations[I]) is TPasProcedure) and (TPasProcedure(Decls.Declarations[I]).Body <> nil) then
        TPasProcedure(Decls.Declarations[I]).Body.ForEachCall(@CollectNested, nil);
  for I := 0 to FNodes.Get.Count - 1 do
  begin
    N := TPasElement(FNodes.Get[I]);
    if Writes then
    begin
      if (N is TPasImplAssign) then
        Written(TPasImplAssign(N).left, N);
      if (N is TParamsExpr) and (TParamsExpr(N).Kind = pekFuncParams) then
      begin
        E := TParamsExpr(N);
        C := E.Value;
        if (C is TBinaryExpr) and (TBinaryExpr(C).OpCode = eopSubIdent) then
          C := TBinaryExpr(C).right;
        D := Ref(C);
        // InterlockedIncrement and the others are atomic: not a race
        if (D is TPasProcedure) and not SameText(Copy(D.Name, 1, 11), 'Interlocked') then
        begin
          Proc := TPasProcedure(D);
          for J := 0 to Length(E.Params) - 1 do
            if (J < Proc.ProcType.Args.Count)
              and (TPasArgument(Proc.ProcType.Args[J]).Access in [argVar, argOut]) then
              Written(E.Params[J], N);
        end
        else if (D is TPasUnresolvedSymbolRef) and (Length(E.Params) > 0) then
          if SameText(D.Name, 'Inc') or SameText(D.Name, 'Dec') or SameText(D.Name, 'SetLength')
            or SameText(D.Name, 'Include') or SameText(D.Name, 'Exclude') or SameText(D.Name, 'Delete') then
            Written(E.Params[0], N)
          else if SameText(D.Name, 'Insert') and (Length(E.Params) > 1) then
            Written(E.Params[1], N);
      end;
      Continue;
    end;
    if not ((N is TParamsExpr) and (TParamsExpr(N).Kind = pekFuncParams)) then
      Continue;
    E := TParamsExpr(N);
    C := E.Value;
    if (C is TBinaryExpr) and (TBinaryExpr(C).OpCode = eopSubIdent) then
      C := TBinaryExpr(C).right;
    D := Ref(C);
    if (D is TPasProcedure) and SameText(D.Name, 'Send') and (D.Parent is TPasRecordType)
      and StartsWithName(D.Parent.Name, 'TChan') and (Length(E.Params) = 1) then
      CheckMove(E.Params[0], FNodes.Get.IndexOf(E.Params[0]), 'Send', 'send')
    else if (D is TPasConstructor) and IsTaskClass(TPasType(D.Parent)) then
      for J := 0 to Length(E.Params) - 1 do
        CheckMove(E.Params[J], FNodes.Get.IndexOf(E.Params[J]), 'The task ' + D.Parent.Name, 'pass');
  end;
end;

procedure TRace.ScanDecls(const Decls: TPasDeclarations);
var
  Pass: Integer;

  procedure Walk(const L: TPasDeclarations; const Writes: Boolean);
  var
    K: Integer;
    R: TPasElement;
  begin
    if L = nil then
      Exit;
    for K := 0 to L.Declarations.Count - 1 do
    begin
      R := TPasElement(L.Declarations[K]);
      if (R is TPasProcedure) and (TPasProcedure(R).Body <> nil) then
      begin
        Scan(TPasProcedure(R).Body.Body, TPasProcedure(R).Body, TPasProcedure(R), Writes);
        Walk(TPasProcedure(R).Body, Writes);
      end;
    end;
  end;

begin
  for Pass := 0 to 1 do
    Walk(Decls, Pass = 0);
end;

{ The declarations of the module that carry values to other goroutines: task fields and channels. }
procedure TRace.CheckTypes(const Decls: TPasDeclarations);
var
  I, J: Integer;
  D, M: TPasElement;
  T: TPasType;

  procedure CheckVar(const V: TPasElement; const VT: TPasElement);
  var
    E: TPasType;
  begin
    E := ChanElem(TypeOf(VT));
    if E <> nil then
      CheckShared(V, E, 'The channel ' + V.Name);
  end;

begin
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    D := TPasElement(Decls.Declarations[I]);
    if D is TPasClassType then
    begin
      for J := 0 to TPasClassType(D).Members.Count - 1 do
      begin
        M := TPasElement(TPasClassType(D).Members[J]);
        if not ((M is TPasVariable) and not (M is TPasConst) and not (M is TPasProperty)) then
          Continue;
        T := TypeOf(TPasVariable(M).VarType);
        if IsTaskClass(TPasClassType(D)) then
          CheckShared(M, T, 'The task field ' + M.Name);
        CheckVar(M, TPasVariable(M).VarType);
      end;
    end
    else if (D is TPasVariable) and not (D is TPasConst) then
      CheckVar(D, TPasVariable(D).VarType)
    else if (D is TPasProcedure) and (TPasProcedure(D).Body <> nil) then
    begin
      for J := 0 to TPasProcedure(D).ProcType.Args.Count - 1 do
        CheckVar(TPasElement(TPasProcedure(D).ProcType.Args[J]),
          TPasArgument(TPasProcedure(D).ProcType.Args[J]).ArgType);
      CheckTypes(TPasProcedure(D).Body);
    end;
  end;
end;

{ The routine with the body of a declared one. }
function TRace.ImplOf(const P: TPasProcedure): TPasProcedure;
begin
  Result := P;
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).ImplProc <> nil) then
    Result := TPasProcedureScope(P.CustomData).ImplProc;
end;

{ The declaration of a routine with a body (in its class for a method). }
function TRace.DeclOf(const P: TPasProcedure): TPasProcedure;
begin
  Result := P;
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    Result := TPasProcedureScope(P.CustomData).DeclarationProc;
end;

{ P overrides the method C, directly or through other overrides: a call of C may run P. }
function TRace.Overrides(const P, C: TPasProcedure): Boolean;
var
  X, Want: TPasProcedure;
  Depth: Integer;
begin
  Want := DeclOf(C);
  X := DeclOf(P);
  Depth := 0;
  while (X <> nil) and (X.CustomData is TPasProcedureScope) and (Depth < 64) do
  begin
    X := TPasProcedureScope(X.CustomData).OverriddenProc;
    if (X <> nil) and (DeclOf(X) = Want) then
      Exit(True);
    Inc(Depth);
  end;
  Result := False;
end;

procedure TRace.AllProcs(const Decls: TPasDeclarations; const All: TFPList);
var
  I: Integer;
  D: TPasElement;
begin
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    D := TPasElement(Decls.Declarations[I]);
    if (D is TPasProcedure) and (TPasProcedure(D).Body <> nil) then
    begin
      All.Add(D);
      AllProcs(TPasProcedure(D).Body, All);
    end;
  end;
end;

{ Go(@Proc) among the nodes in FNodes: Proc runs on another goroutine. }
procedure TRace.GoSites(const Reached: TFPList; const From: TStringList; const All: TFPList);
var
  L: Integer;
  E: TParamsExpr;
  C, A: TPasElement;
begin
  for L := 0 to FNodes.Get.Count - 1 do
  begin
    if not ((TObject(FNodes.Get[L]) is TParamsExpr) and (TParamsExpr(FNodes.Get[L]).Kind = pekFuncParams)) then
      Continue;
    E := TParamsExpr(FNodes.Get[L]);
    C := E.Value;
    if (C is TBinaryExpr) and (TBinaryExpr(C).OpCode = eopSubIdent) then
      C := TBinaryExpr(C).right;
    C := Ref(C);
    if not ((C is TPasProcedure) and SameText(C.Name, 'Go') and (Length(E.Params) = 1)) then
      Continue;
    A := E.Params[0];
    if (A is TUnaryExpr) and (TUnaryExpr(A).OpCode = eopAddress) then
    begin
      A := Ref(TUnaryExpr(A).Operand);
      if A is TPasProcedure then
        Reach(ImplOf(TPasProcedure(A)), A.Name, Reached, From, All);
    end;
  end;
end;

procedure TRace.Reach(const R: TPasProcedure; const Who: String; const Reached: TFPList; const From: TStringList;
  const All: TFPList);
begin
  if (R <> nil) and (All.IndexOf(R) >= 0) and (Reached.IndexOf(R) < 0) then
  begin
    Reached.Add(R);
    From.Add(Who);
  end;
end;

{ A global that goroutines may share by construction: a channel or an RTL lock, or an argument of an Interlocked call. }
function TRace.SyncGlobal(const N: TPasElement; const D: TPasVariable): Boolean;
var
  T: TPasType;
  C: TPasElement;
begin
  T := TypeOf(D.VarType);
  if (T <> nil) and (StartsWithName(T.Name, 'TChan') or SameText(T.Name, 'TRTLCriticalSection')) then
    Exit(True);
  Result := False;
  if (N.Parent is TParamsExpr) and (TParamsExpr(N.Parent).Kind = pekFuncParams) then
  begin
    C := Ref(TParamsExpr(N.Parent).Value);
    Result := (C is TPasProcedure) and SameText(Copy(C.Name, 1, 11), 'Interlocked');
  end;
end;

{ S19 in a program: its globals are the locals of the main goroutine, so a routine that a task reaches (from the Run of a
  task class of the program or a Go(@Proc), through calls and overrides) does not name them. }
procedure TRace.CheckProgramGlobals(const Prog: TPasProgram);
var
  All, Reached: TListBox;
  From: TLinesBox;
  I, J, K: Integer;
  P, Q: TPasProcedure;
  N, D: TPasElement;
begin
  All := TListBox.Own(TFPList.Create);
  Reached := TListBox.Own(TFPList.Create);
  From := TLinesBox.Own(TStringList.Create);
  AllProcs(Prog.ProgramSection, All.Get);
  // the entries: the Run of a task class, the procedures given to Go
  for I := 0 to All.Get.Count - 1 do
  begin
    P := TPasProcedure(All.Get[I]);
    Q := DeclOf(P);
    if (Q.Parent is TPasClassType) and SameText(Q.Name, 'Run') and IsTaskClass(TPasClassType(Q.Parent)) then
      Reach(P, Q.Parent.Name + '.Run', Reached.Get, From.Get, All.Get);
    FNodes.Get.Clear;
    if P.Body.Body <> nil then
      P.Body.Body.ForEachCall(@Collect, nil);
    GoSites(Reached.Get, From.Get, All.Get);
  end;
  FNodes.Get.Clear;
  if Prog.InitializationSection <> nil then
    Prog.InitializationSection.ForEachCall(@Collect, nil);
  GoSites(Reached.Get, From.Get, All.Get);
  // the routines they reach, and the globals those name
  I := 0;
  while I < Reached.Get.Count do
  begin
    P := TPasProcedure(Reached.Get[I]);
    FNodes.Get.Clear;
    if P.Body.Body <> nil then
      P.Body.Body.ForEachCall(@Collect, nil);
    for J := 0 to FNodes.Get.Count - 1 do
    begin
      N := TPasElement(FNodes.Get[J]);
      D := Ref(N);
      if D is TPasProcedure then
      begin
        Reach(ImplOf(TPasProcedure(D)), From.Get[I], Reached.Get, From.Get, All.Get);
        for K := 0 to All.Get.Count - 1 do
          if Overrides(TPasProcedure(All.Get[K]), TPasProcedure(D)) then
            Reach(TPasProcedure(All.Get[K]), From.Get[I], Reached.Get, From.Get, All.Get);
      end
      else if (N is TPrimitiveExpr) and (D is TPasVariable) and not (D is TPasConst) and not (D is TPasProperty)
        and (D.Parent = Prog.ProgramSection) and not IsThreadVar(D) and not SyncGlobal(N, TPasVariable(D)) then
        Add(N, 'S19', Format('the global %s of the program is named in %s, which the task %s reaches: the main '
          + 'goroutine and the task would share it; give the task its own value (a field, a parameter) or send it '
          + 'through a channel', [D.Name, P.Name, From.Get[I]]));
    end;
    Inc(I);
  end;
end;

procedure VetCheckRaces(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);
var
  R: TRaceBox;
  I: Integer;
begin
  for I := 0 to High(Src.Lines) do
    if Pos('// UNSAFE-UNIT:', Src.Lines[I]) = 1 then
      Exit;
  R := TRaceBox.Own(TRace.Create(Src, Resolver, Module));
  // the writes first (S19, and the writes of fields that decide frozenness), then the moves (S11m)
  R.Get.ScanDecls(Module.InterfaceSection);
  R.Get.ScanDecls(Module.ImplementationSection);
  if Module is TPasProgram then
  begin
    R.Get.ScanDecls(TPasProgram(Module).ProgramSection);
    R.Get.Scan(Module.InitializationSection, TPasProgram(Module).ProgramSection, nil, False);
  end;
  if Module is TPasProgram then
    R.Get.CheckProgramGlobals(TPasProgram(Module));
  R.Get.CheckTypes(Module.InterfaceSection);
  R.Get.CheckTypes(Module.ImplementationSection);
  if Module is TPasProgram then
    R.Get.CheckTypes(TPasProgram(Module).ProgramSection);
  for I := 0 to High(R.Get.FReport.Findings) do
    with R.Get.FReport.Findings[I] do
      VetAdd(Report, FileName, Row, Col, Severity, Rule, Msg);
end;

end.
