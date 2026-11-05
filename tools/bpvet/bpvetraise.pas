{ SPDX-License-Identifier: MIT }
{ bpvet rule S30 (safe/SPEC.md §24.5): the exception classes a routine may raise, a mark of fact (§24.2) written as
  // raises: EConvertError, EInOutError
  on the header line of the routine or on a comment line right above it. It runs in the typed mode on a module that
  resolved (bpvettyped.pas).

  The set of a routine: the class of each `raise X` in its body (the static type of X) and the sets of the routines it
  calls, minus what a `try ... except` around them handles; a re-raise (`raise;`, or `raise E` of the variable of an
  `on E: X do` handler) raises again what its handler took. The sets of the routines of the module grow together until
  no body adds a class (a fixpoint, so recursion is fine). The set of a callee:
    a routine of the module with a body: its inferred set;
    a routine of a used unit, or one of the module without a body (abstract, external): its // raises: mark (nothing
    when there is none);
    a routine of the RTL (the declaration stubs): the table RtlRaises below (nothing for the routines outside it);
    a call through a procedure variable or a method pointer, a property getter: nothing; a virtual method: the set of
    the method the call names, not those of its overrides.
  So the mark lists what the code of the module and the marks of its units show; it is documentation, not a proof that
  nothing else is raised (EOutOfMemory, a run-time error under -Cr, an RTL routine outside the table).
  A handler `on E: X` takes a class that is X or descends from it; a class whose ancestors are not known (named only
  in a mark) is taken as a descendant of Exception. A bare `except` and an `else` take everything.

    Error  a routine declared in the interface of a unit (a method of a class there that is not private included; an
           operator excluded) whose set is not empty and that has no mark;
    Error  a mark on a routine with a body that lists other classes than its set (fewer or more).
  --fix (RaiseFix) writes the mark at the end of the header line of the declaration (on a line of its own above the
  header when the line would grow past 120 characters), rewrites a wrong list, and removes the mark of an empty set;
  in the checked file only (a declaration in an include file keeps its finding). }
unit BpvetRaise;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, PasTree, PasResolveEval, PasResolver, BpvetCore, Safe;

var
  { --fix: S30 writes the // raises: marks into the file (after S17 and S24 have written theirs) }
  RaiseFix: Boolean = False;

{ RtlDir: the directory of the declaration stubs; a routine declared there takes its set from the table. }
procedure VetCheckRaises(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  const RtlDir: String; var Report: TVetReport);

implementation

type
  TLinesBox = specialize TOwned<TStringList>;
  TListBox = specialize TOwned<TFPList>;

  { A // raises: mark found in the text: Row 0 when there is none. }
  TMark = record
    FileName: String;
    Row: Integer;
    Names: String;   // the set, ",a,b," in lower case; '' for an empty list
  end;

  { A change of the file: Above inserts Text as a line above Row; otherwise the mark on Row gets the list Text ('':
    the mark goes), or Text is appended when the line has no mark. }
  TEdit = record
    Row: Integer;
    Above: Boolean;
    Text: String;
  end;

  TRaise = class
  private
    FSrc: TVetSource;
    FResolver: TPasResolver;   // borrow: the resolver of the checked module, alive during the check
    FModule: TPasModule;       // borrow: the checked module
    FRtlDir: String;
    FReport: TVetReport;
    FLines: TLinesBox;         // name=file for the sources of include files and used units
    FIndex: TLinesBox;         // sorted: the key of a routine with a body, its index in FProcs as the object
    FProcs: TListBox;          // the routines of the module with a body
    FSets: array of String;    // the inferred set of FProcs[I]
    FNodes: TListBox;          // the raise statements and the calls of every routine of FProcs, in their order
    FFrom: array of Integer;   // the nodes of FProcs[I] are FNodes[FFrom[I]] .. FNodes[FFrom[I + 1] - 1]
    FFirst, FLast: Integer;    // the nodes of the routine being inferred
    FFiles: TLinesBox;         // sorted: a file name, what it is as the object (FileKind)
    FCallees: TLinesBox;       // sorted: the key of a routine outside FProcs=its set (it does not change)
    FDisplay: TLinesBox;       // lower case name=the name as written
    FChains: TLinesBox;        // lower case name=",name,ancestor,...," of a class
    FEdits: array of TEdit;
    procedure Collect(El: TPasElement; Arg: Pointer);
    procedure Index(const Decls: TPasDeclarations);
    function Key(const P: TPasProcedure): String;
    function Decl(const P: TPasProcedure): TPasProcedure;
    function Ref(const E: TPasElement): TPasElement;
    function TypeOf(const E: TPasElement): TPasType;
    function FileKind(const FileName: String): Integer;
    function LineOf(const FileName: String; const Row: Integer): String;
    function InMainFile(const El: TPasElement): Boolean;
    function ModuleOf(const El: TPasElement): TPasModule;
    function FromRtl(const El: TPasElement): Boolean;
    function MarkOf(const El: TPasElement): TMark;
    procedure Remember(const N: String; const Strong: Boolean);
    function Shown(const S: String): String;
    function ChainOf(const C: TPasClassType): String;
    function FindClass(const N: String): TPasClassType;
    function Ancestors(const N: String): String;
    function Takes(const N, Handler: String): Boolean;
    function HandlerName(const H: TPasImplExceptOn): String;
    function Uncaught(const T: TPasImplTry; const S: String): String;
    function Lift(const N: TPasElement; const Stop: TPasElement; var S: String): Boolean;
    function Guarded(const T: TPasImplTry): String;
    function Reraised(const N: TPasElement): String;
    function IsCall(const N: TPasElement): Boolean;
    function CalleeSet(const P: TPasProcedure): String;
    function Outside(const P: TPasProcedure): String;
    function Raw(const N: TPasElement): String;
    function Infer(const K: Integer): String;
    function Exported(const D: TPasProcedure): Boolean;
    procedure Add(const At: TPasElement; const Row: Integer; const Msg: String);
    procedure Edit(const Row: Integer; const Above: Boolean; const Text: String);
    procedure Check(const I: Integer);
    procedure ApplyEdits;
  public
    constructor Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule;
      const ARtlDir: String);
    procedure Run;
    property Report: TVetReport read FReport;
  end;

  TRaiseBox = specialize TOwned<TRaise>;

const
  { The longest header line --fix makes; past it the mark goes on a line of its own above the header. }
  MaxLine = 120;
  Mark = '// raises:';

  { What routines of the RTL raise on their input (FPC 3.2.2): unit.routine or unit.class.method = the classes. Format
    is left out: its EConvertError is a wrong format string, a bug that the check of format strings finds (§22), not
    an error of the input; so are the run-time errors. }
  RtlRaises: array[0..18] of String = (
    'sysutils.strtoint=EConvertError', 'sysutils.strtoint64=EConvertError', 'sysutils.strtoqword=EConvertError',
    'sysutils.strtodword=EConvertError', 'sysutils.strtouint64=EConvertError', 'sysutils.strtofloat=EConvertError',
    'sysutils.strtocurr=EConvertError', 'sysutils.strtobool=EConvertError', 'sysutils.strtodate=EConvertError',
    'sysutils.strtotime=EConvertError', 'sysutils.strtodatetime=EConvertError', 'sysutils.encodedate=EConvertError',
    'sysutils.encodetime=EConvertError', 'classes.tfilestream.create=EFCreateError,EFOpenError', 'classes.tstrings.loadfromfile=EFOpenError',
    'classes.tstrings.savetofile=EFCreateError', 'classes.tstream.readbuffer=EReadError',
    'classes.tstream.writebuffer=EWriteError', 'classes.tstream.copyfrom=EReadError,EWriteError');

  { The ancestors of the classes of the table, for a module whose stubs do not hold them. }
  RtlChains: array[0..7] of String = (
    'econverterror=,econverterror,exception,tobject,',
    'estreamerror=,estreamerror,exception,tobject,',
    'efcreateerror=,efcreateerror,estreamerror,exception,tobject,',
    'efopenerror=,efopenerror,estreamerror,exception,tobject,',
    'efilererror=,efilererror,estreamerror,exception,tobject,',
    'ereaderror=,ereaderror,efilererror,estreamerror,exception,tobject,',
    'ewriteerror=,ewriteerror,efilererror,estreamerror,exception,tobject,',
    'exception=,exception,tobject,');

{ ---------- sets: ",a,b," in lower case, '' when empty ---------- }

function Has(const S, N: String): Boolean;
begin
  Result := Pos(',' + N + ',', S) > 0;
end;

procedure Include(var S: String; const N: String);
begin
  if N = '' then
    Exit;
  if S = '' then
    S := ',';
  if not Has(S, N) then
    S := S + N + ',';
end;

procedure Union(var S: String; const T: String);
var
  N: String;
begin
  for N in T.Split([','], TStringSplitOptions.ExcludeEmpty) do
    Include(S, N);
end;

{ The members of S, sorted. }
function Members(const S: String): TStringArray;
var
  L: TLinesBox;
  I: Integer;
  N: String;
begin
  L := TLinesBox.Own(TStringList.Create);
  L.Get.Sorted := True;
  L.Get.Duplicates := dupIgnore;
  for N in S.Split([','], TStringSplitOptions.ExcludeEmpty) do
    L.Get.Add(N);
  Result := nil;
  SetLength(Result, L.Get.Count);
  for I := 0 to L.Get.Count - 1 do
    Result[I] := L.Get[I];
end;

function SameSet(const A, B: String): Boolean;
begin
  Result := String.Join(',', Members(A)) = String.Join(',', Members(B));
end;

function IsIdent(const C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

{ The list after the mark at P of Line: the position after it in Last; the names in lower case into Names and as
  written into Written (separated by commas). }
procedure ParseList(const Line: String; const P: Integer; out Last: Integer; out Names, Written: String);
var
  I, J: Integer;
begin
  Names := '';
  Written := '';
  I := P + Length(Mark);
  Last := I;
  repeat
    while (I <= Length(Line)) and (Line[I] = ' ') do
      Inc(I);
    J := I;
    while (I <= Length(Line)) and (IsIdent(Line[I]) or (Line[I] = '.')) do
      Inc(I);
    if I = J then
      Break;
    Include(Names, LowerCase(Copy(Line, J, I - J)));
    if Written <> '' then
      Written := Written + ',';
    Written := Written + Copy(Line, J, I - J);
    Last := I;
    while (I <= Length(Line)) and (Line[I] = ' ') do
      Inc(I);
    if (I > Length(Line)) or (Line[I] <> ',') then
      Break;
    Inc(I);
  until False;
end;

{ ---------- TRaise ---------- }

constructor TRaise.Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule;
  const ARtlDir: String);
begin
  inherited Create;
  FSrc := ASrc;
  // borrow: the resolver outlives the check (VetResolve)
  FResolver := AResolver;
  // borrow: the module outlives the check (VetResolve)
  FModule := AModule;
  FRtlDir := '';
  if ARtlDir <> '' then
    FRtlDir := IncludeTrailingPathDelimiter(ExpandFileName(ARtlDir));
  FLines := TLinesBox.Own(TStringList.Create);
  FLines.Get.OwnsObjects := True;
  FIndex := TLinesBox.Own(TStringList.Create);
  FIndex.Get.Sorted := True;
  FProcs := TListBox.Own(TFPList.Create);
  FNodes := TListBox.Own(TFPList.Create);
  FFiles := TLinesBox.Own(TStringList.Create);
  FFiles.Get.Sorted := True;
  FCallees := TLinesBox.Own(TStringList.Create);
  FCallees.Get.Sorted := True;
  FLines.Get.Sorted := True;
  FDisplay := TLinesBox.Own(TStringList.Create);
  FChains := TLinesBox.Own(TStringList.Create);
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure TRaise.Collect(El: TPasElement; Arg: Pointer);
begin
  if (El is TPasImplRaise) or IsCall(El) then
    FNodes.Get.Add(El);
end;

function TRaise.Decl(const P: TPasProcedure): TPasProcedure;
begin
  Result := P;
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    Result := TPasProcedureScope(P.CustomData).DeclarationProc;
end;

function TRaise.Key(const P: TPasProcedure): String;
begin
  Result := IntToHex(PtrUInt(Decl(P)), 16);
end;

{ The routines of Decls that have a body, the nested ones too. }
procedure TRaise.Index(const Decls: TPasDeclarations);
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
      FIndex.Get.AddObject(Key(TPasProcedure(D)), TObject(PtrInt(FProcs.Get.Count)));
      FProcs.Get.Add(D);
      // the nodes that raise are collected once; the passes of the fixpoint read them
      SetLength(FFrom, FProcs.Get.Count + 1);
      if TPasProcedure(D).Body.Body <> nil then
        TPasProcedure(D).Body.Body.ForEachCall(@Collect, nil);
      FFrom[FProcs.Get.Count] := FNodes.Get.Count;
      Index(TPasProcedure(D).Body);
    end;
  end;
end;

function TRaise.Ref(const E: TPasElement): TPasElement;
begin
  Result := nil;
  if (E <> nil) and (E.CustomData is TResolvedReference) then
    Result := TResolvedReference(E.CustomData).Declaration;
end;

function TRaise.TypeOf(const E: TPasElement): TPasType;
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

{ 1: the checked file (or no file), 2: a file of the RTL stubs, 0: another file. Kept per name: a file name is expanded
  once. }
function TRaise.FileKind(const FileName: String): Integer;
var
  I: Integer;
  F: String;
begin
  if FileName = '' then
    Exit(1);
  if FFiles.Get.Find(FileName, I) then
    Exit(PtrInt(FFiles.Get.Objects[I]));
  F := ExpandFileName(FileName);
  Result := 0;
  if SameFileName(F, ExpandFileName(FSrc.FileName)) then
    Result := 1
  else if (FRtlDir <> '') and SameFileName(IncludeTrailingPathDelimiter(ExtractFileDir(F)), FRtlDir) then
    Result := 2;
  FFiles.Get.AddObject(FileName, TObject(PtrInt(Result)));
end;

function TRaise.LineOf(const FileName: String; const Row: Integer): String;
var
  I: Integer;
  L: TStringList;
begin
  if FileKind(FileName) = 1 then
    Exit(VetLine(FSrc, Row));
  if not FLines.Get.Find(FileName, I) then
  begin
    // UNSAFE: the list FLines owns the loaded source (OwnsObjects)
    L := TStringList.Create;
    try
      L.LoadFromFile(FileName);
    except
      L.Clear;
    end;
    I := FLines.Get.AddObject(FileName, L);
  end;
  L := TStringList(FLines.Get.Objects[I]);
  if (Row >= 1) and (Row <= L.Count) then
    Result := L[Row - 1]
  else
    Result := '';
end;

function TRaise.InMainFile(const El: TPasElement): Boolean;
begin
  Result := FileKind(El.SourceFilename) = 1;
end;

function TRaise.ModuleOf(const El: TPasElement): TPasModule;
var
  X: TPasElement;
begin
  X := El;
  while (X <> nil) and not (X is TPasModule) do
    X := X.Parent;
  Result := nil;
  if X is TPasModule then
    Result := TPasModule(X);
end;

function TRaise.FromRtl(const El: TPasElement): Boolean;
begin
  Result := FileKind(El.SourceFilename) = 2;
end;

{ The mark of El: on its line, or on a comment line right above it (more comment lines may be between). }
function TRaise.MarkOf(const El: TPasElement): TMark;
var
  Row, P, Last: Integer;
  Line, Written, N: String;
begin
  Result.FileName := El.SourceFilename;
  Result.Row := 0;
  Result.Names := '';
  Row := El.SourceLinenumber;
  repeat
    Line := LineOf(El.SourceFilename, Row);
    if (Row <> El.SourceLinenumber) and (Copy(TrimLeft(Line), 1, 2) <> '//') then
      Exit;
    P := Pos(Mark, Line);
    if P > 0 then
    begin
      Result.Row := Row;
      ParseList(Line, P, Last, Result.Names, Written);
      for N in Written.Split([','], TStringSplitOptions.ExcludeEmpty) do
        Remember(N, False);
      Exit;
    end;
    Dec(Row);
  until Row < 1;
end;

{ Keeps how a class name is written; a name from a declaration (Strong) wins over one from a mark. }
procedure TRaise.Remember(const N: String; const Strong: Boolean);
var
  I: Integer;
begin
  I := FDisplay.Get.IndexOfName(LowerCase(N));
  if I < 0 then
    FDisplay.Get.Add(LowerCase(N) + '=' + N)
  else if Strong then
    FDisplay.Get.ValueFromIndex[I] := N;
end;

{ The set as a list for a message or a mark: "EConvertError, EInOutError". }
function TRaise.Shown(const S: String): String;
var
  N, W: String;
begin
  Result := '';
  for N in Members(S) do
  begin
    W := FDisplay.Get.Values[N];
    if W = '' then
      W := N;
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + W;
  end;
end;

{ ",name,ancestor,...," of C; a chain that does not resolve ends in Exception. }
function TRaise.ChainOf(const C: TPasClassType): String;
var
  X: TPasType;
  Depth: Integer;
begin
  Result := ',';
  X := C;
  Depth := 0;
  while (X is TPasClassType) and (Depth < 64) do
  begin
    Result := Result + LowerCase(X.Name) + ',';
    if TPasClassType(X).AncestorType = nil then
    begin
      if not SameText(X.Name, 'TObject') then
        Result := Result + 'tobject,';
      Exit;
    end;
    X := TypeOf(TPasClassType(X).AncestorType);
    Inc(Depth);
  end;
  Include(Result, 'exception');
  Include(Result, 'tobject');
end;

{ The class named N in the module and in the units it uses (their interfaces), or nil. }
function TRaise.FindClass(const N: String): TPasClassType;
var
  Seen: TListBox;

  function InDecls(const Decls: TPasDeclarations): TPasClassType;
  var
    I: Integer;
    D: TPasElement;
  begin
    Result := nil;
    if Decls = nil then
      Exit;
    for I := 0 to Decls.Declarations.Count - 1 do
    begin
      D := TPasElement(Decls.Declarations[I]);
      if (D is TPasClassType) and SameText(D.Name, N) and not TPasClassType(D).IsForward then
        Exit(TPasClassType(D));
    end;
  end;

  function InModule(const M: TPasModule; const Own: Boolean): TPasClassType;
  var
    I: Integer;
    Sec: TPasSection;
    U: TPasElement;
  begin
    Result := nil;
    if (M = nil) or (Seen.Get.IndexOf(M) >= 0) then
      Exit;
    Seen.Get.Add(M);
    Result := InDecls(M.InterfaceSection);
    if (Result = nil) and Own then
    begin
      Result := InDecls(M.ImplementationSection);
      if (Result = nil) and (M is TPasProgram) then
        Result := InDecls(TPasProgram(M).ProgramSection);
    end;
    if Result <> nil then
      Exit;
    Sec := M.InterfaceSection;
    if M is TPasProgram then
      Sec := TPasProgram(M).ProgramSection;
    if Sec = nil then
      Exit;
    for I := 0 to High(Sec.UsesClause) do
    begin
      U := Sec.UsesClause[I].Module;
      if U is TPasModule then
      begin
        Result := InModule(TPasModule(U), False);
        if Result <> nil then
          Exit;
      end;
    end;
    if Own and (M.ImplementationSection <> nil) then
      for I := 0 to High(M.ImplementationSection.UsesClause) do
      begin
        U := M.ImplementationSection.UsesClause[I].Module;
        if U is TPasModule then
        begin
          Result := InModule(TPasModule(U), False);
          if Result <> nil then
            Exit;
        end;
      end;
  end;

begin
  Seen := TListBox.Own(TFPList.Create);
  Result := InModule(FModule, True);
end;

{ ",n,ancestor,...," of the class named N (lower case). }
function TRaise.Ancestors(const N: String): String;
var
  I: Integer;
  C: TPasClassType;
begin
  I := FChains.Get.IndexOfName(N);
  if I >= 0 then
    Exit(FChains.Get.ValueFromIndex[I]);
  C := FindClass(N);
  if C <> nil then
    Result := ChainOf(C)
  else
  begin
    Result := '';
    for I := 0 to High(RtlChains) do
      if Copy(RtlChains[I], 1, Length(N) + 1) = N + '=' then
        Result := Copy(RtlChains[I], Length(N) + 2, Length(RtlChains[I]));
    if Result = '' then
      Result := ',' + N + ',exception,tobject,';
  end;
  FChains.Get.Add(N + '=' + Result);
end;

{ A handler of the class Handler (lower case) takes a raised N. }
function TRaise.Takes(const N, Handler: String): Boolean;
begin
  Result := Has(Ancestors(N), Handler);
end;

function TRaise.HandlerName(const H: TPasImplExceptOn): String;
var
  T: TPasType;
begin
  T := TypeOf(H.TypeEl);
  if T is TPasClassType then
    Result := LowerCase(T.Name)
  else
    Result := LowerCase(H.TypeName);
  if Pos('.', Result) > 0 then
    Result := Copy(Result, LastDelimiter('.', Result) + 1, Length(Result));
end;

{ What of S leaves the protected part of T. }
function TRaise.Uncaught(const T: TPasImplTry; const S: String): String;
var
  E: TPasImplTryHandler;
  I: Integer;
  N: String;
  Taken: Boolean;
begin
  E := T.FinallyExcept;
  if not (E is TPasImplTryExcept) or (S = '') then
    Exit(S);
  if T.ElseBranch <> nil then
    Exit('');
  for I := 0 to E.Elements.Count - 1 do
    if not (TObject(E.Elements[I]) is TPasImplExceptOn) then
      Exit(''); // a bare except
  Result := '';
  for N in S.Split([','], TStringSplitOptions.ExcludeEmpty) do
  begin
    Taken := False;
    for I := 0 to E.Elements.Count - 1 do
      Taken := Taken or Takes(N, HandlerName(TPasImplExceptOn(E.Elements[I])));
    if not Taken then
      Include(Result, N);
  end;
end;

{ Carries S from N up through the try statements around it until Stop (nil: the body of the routine); a class that a
  handler around the protected part takes leaves S. True when Stop was reached from its protected part. }
function TRaise.Lift(const N: TPasElement; const Stop: TPasElement; var S: String): Boolean;
var
  C, P: TPasElement;
begin
  C := N;
  P := N.Parent;
  while P <> nil do
  begin
    if P is TPasImplTry then
    begin
      if (C = TPasImplTry(P).FinallyExcept) or (C = TPasImplTry(P).ElseBranch) then
      begin
        if P = Stop then
          Exit(False);
      end
      else
      begin
        if P = Stop then
          Exit(True);
        S := Uncaught(TPasImplTry(P), S);
      end;
    end
    else if (P = Stop) or (P is TProcedureBody) or (P is TPasProcedure) then
      Exit(False);
    C := P;
    P := P.Parent;
  end;
  Result := False;
end;

{ What the protected part of T raises, before its handlers. }
function TRaise.Guarded(const T: TPasImplTry): String;
var
  I: Integer;
  N: TPasElement;
  S: String;
begin
  Result := '';
  for I := FFirst to FLast do
  begin
    N := TPasElement(FNodes.Get[I]);
    // only a node of the protected part: a re-raise in a handler of T would ask for this set again
    S := '';
    if not Lift(N, T, S) then
      Continue;
    S := Raw(N);
    Lift(N, T, S);
    Union(Result, S);
  end;
end;

{ A re-raise at N raises again what its handler took. }
function TRaise.Reraised(const N: TPasElement): String;
var
  P: TPasElement;
  T: TPasImplTry;
  E: TPasImplTryHandler;
  S, M: String;
  I: Integer;
  First: TPasImplExceptOn;
begin
  Result := '';
  P := N.Parent;
  while (P <> nil) and not (P is TProcedureBody) and not (P is TPasProcedure) do
  begin
    if (P is TPasImplExceptOn) or (P is TPasImplTryExcept) or (P is TPasImplTryExceptElse) then
      Break;
    P := P.Parent;
  end;
  if P is TPasImplExceptOn then
  begin
    E := P.Parent as TPasImplTryHandler;
    T := E.Parent as TPasImplTry;
    S := Guarded(T);
    for M in S.Split([','], TStringSplitOptions.ExcludeEmpty) do
    begin
      // the first handler that takes the class runs
      First := nil;
      for I := 0 to E.Elements.Count - 1 do
        if (First = nil) and (TObject(E.Elements[I]) is TPasImplExceptOn)
          and Takes(M, HandlerName(TPasImplExceptOn(E.Elements[I]))) then
          First := TPasImplExceptOn(E.Elements[I]);
      if First = P then
        Include(Result, M);
    end;
  end
  else if P is TPasImplTryExcept then
    Result := Guarded(P.Parent as TPasImplTry)
  else if P is TPasImplTryExceptElse then
  begin
    T := P.Parent as TPasImplTry;
    S := Guarded(T);
    E := T.FinallyExcept;
    for M in S.Split([','], TStringSplitOptions.ExcludeEmpty) do
    begin
      First := nil;
      for I := 0 to E.Elements.Count - 1 do
        if (First = nil) and (TObject(E.Elements[I]) is TPasImplExceptOn)
          and Takes(M, HandlerName(TPasImplExceptOn(E.Elements[I]))) then
          First := TPasImplExceptOn(E.Elements[I]);
      if First = nil then
        Include(Result, M);
    end;
  end;
end;

{ N names a routine and calls it: not @Routine. }
function TRaise.IsCall(const N: TPasElement): Boolean;
var
  X: TPasElement;
begin
  Result := False;
  if not (N is TPasExpr) or not (Ref(N) is TPasProcedure) then
    Exit;
  X := N;
  while (X.Parent is TBinaryExpr) and (TBinaryExpr(X.Parent).OpCode = eopSubIdent)
    and (TBinaryExpr(X.Parent).right = X) do
    X := X.Parent;
  Result := not ((X.Parent is TUnaryExpr) and (TUnaryExpr(X.Parent).OpCode = eopAddress));
end;

function TRaise.CalleeSet(const P: TPasProcedure): String;
var
  I: Integer;
  K: String;
begin
  Result := '';
  K := Key(P);
  if FIndex.Get.Find(K, I) then
    Exit(FSets[PtrInt(FIndex.Get.Objects[I])]);
  if FCallees.Get.Find(K, I) then
    Exit(FCallees.Get.ValueFromIndex[I]);
  Result := Outside(P);
  FCallees.Get.Add(K + '=' + Result);
end;

{ The set of a routine without a body in the module: the table for the RTL, else its mark. }
function TRaise.Outside(const P: TPasProcedure): String;
var
  I: Integer;
  K, N: String;
  M: TPasModule;
  D: TPasProcedure;
begin
  Result := '';
  D := Decl(P);
  M := ModuleOf(D);
  if (M <> FModule) and FromRtl(D) then
  begin
    K := '';
    if M <> nil then
      K := LowerCase(M.Name) + '.';
    if D.Parent is TPasClassType then
      K := K + LowerCase(D.Parent.Name) + '.';
    K := K + LowerCase(D.Name) + '=';
    for I := 0 to High(RtlRaises) do
      if Copy(RtlRaises[I], 1, Length(K)) = K then
        for N in Copy(RtlRaises[I], Length(K) + 1, Length(RtlRaises[I])).Split([',']) do
        begin
          Remember(N, False);
          Include(Result, LowerCase(N));
        end;
    Exit;
  end;
  Result := MarkOf(D).Names;
end;

{ What the node N raises by itself: a raise statement, a call. }
function TRaise.Raw(const N: TPasElement): String;
var
  X: TPasElement;
  T: TPasType;
  R: TPasImplRaise;
begin
  Result := '';
  if N is TPasImplRaise then
  begin
    R := TPasImplRaise(N);
    if R.ExceptObject = nil then
      Exit(Reraised(N));
    // raise E of the variable of its handler: a re-raise
    X := Ref(R.ExceptObject);
    if (X is TPasVariable) and (X.Parent is TPasImplExceptOn) then
      Exit(Reraised(N));
    T := TypeOf(R.ExceptObject);
    if T is TPasClassType then
    begin
      Remember(T.Name, True);
      if FChains.Get.IndexOfName(LowerCase(T.Name)) < 0 then
        FChains.Get.Add(LowerCase(T.Name) + '=' + ChainOf(TPasClassType(T)));
      Include(Result, LowerCase(T.Name));
    end;
  end
  else if IsCall(N) then
    Result := CalleeSet(TPasProcedure(Ref(N)));
end;

{ The set of FProcs[K] from its nodes and the sets known so far. }
function TRaise.Infer(const K: Integer): String;
var
  I: Integer;
  N: TPasElement;
  S: String;
begin
  Result := '';
  FFirst := FFrom[K];
  FLast := FFrom[K + 1] - 1;
  for I := FFirst to FLast do
  begin
    N := TPasElement(FNodes.Get[I]);
    S := Raw(N);
    if S <> '' then
    begin
      Lift(N, nil, S);
      Union(Result, S);
    end;
  end;
end;

{ D is declared in the interface of the unit (a routine, or a method of a type declared there that is not private), and
  is not an operator. }
function TRaise.Exported(const D: TPasProcedure): Boolean;
var
  X: TPasElement;
begin
  // an operator is not called by name, so no caller reads a mark on it
  if (D is TPasOperator) or ((D.Parent is TPasMembersType) and (D.Visibility in [visPrivate, visStrictPrivate])) then
    Exit(False);
  X := D;
  while (X <> nil) and not (X is TPasSection) do
    X := X.Parent;
  Result := (X <> nil) and (X = FModule.InterfaceSection);
end;

procedure TRaise.Add(const At: TPasElement; const Row: Integer; const Msg: String);
var
  FileName: String;
begin
  FileName := FSrc.FileName;
  if not InMainFile(At) then
    FileName := At.SourceFilename;
  VetAdd(FReport, FileName, Row, VetWordColumn(LineOf(At.SourceFilename, Row), At.Name), vsError, 'S30', Msg);
end;

procedure TRaise.Edit(const Row: Integer; const Above: Boolean; const Text: String);
var
  N: Integer;
begin
  N := Length(FEdits);
  SetLength(FEdits, N + 1);
  FEdits[N].Row := Row;
  FEdits[N].Above := Above;
  FEdits[N].Text := Text;
end;

{ The marks of FProcs[I] against its set. }
procedure TRaise.Check(const I: Integer);
var
  P, D: TPasProcedure;
  S, Line: String;
  MD, MI: TMark;
  Fixable: Boolean;

  procedure Wrong(const M: TMark; const At: TPasElement);
  begin
    Fixable := RaiseFix and InMainFile(At);
    if Fixable then
      Edit(M.Row, False, Shown(S))
    else if S = '' then
      Add(At, M.Row, Format('the mark // raises: %s of %s names classes that its code does not raise; remove it '
        + '(bpvet --fix does)', [Shown(M.Names), D.Name]))
    else
      Add(At, M.Row, Format('the mark // raises: %s of %s is not what its code raises: %s; write // raises: %s '
        + '(bpvet --fix does)', [Shown(M.Names), D.Name, Shown(S), Shown(S)]));
  end;

begin
  P := TPasProcedure(FProcs.Get[I]);
  D := Decl(P);
  S := FSets[I];
  MD := MarkOf(D);
  MI.Row := 0;
  if P <> D then
    MI := MarkOf(P);
  if (MD.Row > 0) and not SameSet(MD.Names, S) then
    Wrong(MD, D);
  if (MI.Row > 0) and not SameSet(MI.Names, S) then
    Wrong(MI, P);
  if (S = '') or (MD.Row > 0) or (MI.Row > 0) or not Exported(D) then
    Exit;
  if RaiseFix and InMainFile(D) then
  begin
    Line := VetLine(FSrc, D.SourceLinenumber);
    Edit(D.SourceLinenumber, Length(TrimRight(Line)) + Length('  ' + Mark + ' ' + Shown(S)) > MaxLine, Shown(S));
  end
  else
    Add(D, D.SourceLinenumber, Format('%s may raise %s: a routine of the interface says so with // raises: %s on '
      + 'its header line (bpvet --fix writes it)', [D.Name, Shown(S), Shown(S)]));
end;

{ Writes the marks. The file is read again, since S17 and S24 have written into it; neither adds or removes lines,
  so the rows stay. From the last row up, so that an inserted line moves no row still to be changed. }
procedure TRaise.ApplyEdits;
var
  Lines: TLinesBox;
  I, J, Row, P, Last: Integer;
  Line, Names, Written, Indent: String;
  Done: array of Boolean;
begin
  if Length(FEdits) = 0 then
    Exit;
  Lines := TLinesBox.Own(TStringList.Create);
  try
    Lines.Get.LoadFromFile(FSrc.FileName);
  except
    on Exception do
      Exit;
  end;
  SetLength(Done, Length(FEdits));
  for I := 0 to High(FEdits) do
  begin
    // the edit with the greatest row not done yet
    J := -1;
    for Row := 0 to High(FEdits) do
      if not Done[Row] and ((J < 0) or (FEdits[Row].Row > FEdits[J].Row)) then
        J := Row;
    Done[J] := True;
    Row := FEdits[J].Row;
    if (Row < 1) or (Row > Lines.Get.Count) then
      Continue;
    Line := Lines.Get[Row - 1];
    P := Pos(Mark, Line);
    if FEdits[J].Above then
    begin
      Indent := Copy(Line, 1, Length(Line) - Length(TrimLeft(Line)));
      Lines.Get.Insert(Row - 1, Indent + Mark + ' ' + FEdits[J].Text);
    end
    else if P = 0 then
      Lines.Get[Row - 1] := TrimRight(Line) + '  ' + Mark + ' ' + FEdits[J].Text
    else if FEdits[J].Text <> '' then
    begin
      ParseList(Line, P, Last, Names, Written);
      Lines.Get[Row - 1] := Copy(Line, 1, P + Length(Mark) - 1) + ' ' + FEdits[J].Text
        + Copy(Line, Last, Length(Line));
    end
    else
    begin
      // the mark goes; a line that held only the mark goes with it
      ParseList(Line, P, Last, Names, Written);
      Line := TrimRight(Copy(Line, 1, P - 1)) + Copy(Line, Last, Length(Line));
      if Trim(Line) = '' then
        Lines.Get.Delete(Row - 1)
      else
        Lines.Get[Row - 1] := TrimRight(Line);
    end;
  end;
  Lines.Get.SaveToFile(FSrc.FileName);
end;

procedure TRaise.Run;
var
  I, Pass: Integer;
  S: String;
  Changed: Boolean;
begin
  SetLength(FFrom, 1);
  FFrom[0] := 0;
  Index(FModule.InterfaceSection);
  Index(FModule.ImplementationSection);
  if FModule is TPasProgram then
    Index(TPasProgram(FModule).ProgramSection);
  SetLength(FSets, FProcs.Get.Count);
  // the sets grow until no body adds a class; a set only grows (Union appends), so this ends
  Pass := 0;
  repeat
    Changed := False;
    for I := 0 to FProcs.Get.Count - 1 do
    begin
      if FFrom[I + 1] = FFrom[I] then
        Continue;
      S := FSets[I];
      Union(S, Infer(I));
      if Length(S) <> Length(FSets[I]) then
      begin
        FSets[I] := S;
        Changed := True;
      end;
    end;
    Inc(Pass);
  until not Changed or (Pass >= 64);
  for I := 0 to FProcs.Get.Count - 1 do
    Check(I);
  if RaiseFix then
    ApplyEdits;
end;

procedure VetCheckRaises(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  const RtlDir: String; var Report: TVetReport);
var
  R: TRaiseBox;
  I: Integer;
begin
  R := TRaiseBox.Own(TRaise.Create(Src, Resolver, Module, RtlDir));
  R.Get.Run;
  for I := 0 to High(R.Get.Report.Findings) do
    with R.Get.Report.Findings[I] do
      VetAdd(Report, FileName, Row, Col, Severity, Rule, Msg);
end;

end.
