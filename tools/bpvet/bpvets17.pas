{ SPDX-License-Identifier: MIT }
{ bpvet rule S17 (safe/SPEC.md §20, the root analysis of the region style), the early version of step 8 of
  unxed/bp#108: rules 1-4 inside a routine and through the signatures of the routines it calls. It runs in the typed
  mode on a module that resolved (bpvettyped.pas). The design: the comment of 04-11-2026 in unxed/bp#108.

  A value of the region style has roots: the TRegion it lives in. Only such values have roots (an object of a class
  derived from TRegionObject, a TGrowArray<T>, what is read out of them), so code without regions has no findings. }
unit BpvetS17;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, PasTree, PasResolveEval, PasResolver, BpvetCore, Safe;

{ Checks the routines of Module; Resolver is the one that resolved it. }
procedure VetCheckS17(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);

var
  { bpvet --fix: S17 writes the // root: marks it infers onto the headers of the exported routines. }
  S17Fix: Boolean = False;

implementation

type
  TRoots = Int64;  // a set of roots: bit 0 is the current region of the caller, the others index TS17.FRoots

  TRootKind = (rkCaller, rkParam, rkRegion);

  TRootInfo = record
    Kind: TRootKind;
    Decl: TPasElement;   // the parameter or the local TRegion variable; nil for the caller and for Self
    Name: String;
    Order: Integer;      // a region: when it was created (a later one is an inner one)
  end;

  TVarKind = (vkLocal, vkResult, vkByRef, vkOuter);

  TVarInfo = record
    Decl: TPasElement;
    Kind: TVarKind;
    Roots: TRoots;
    Dead: String;        // the region whose Reset or Release freed what the variable refers to; '' while it is valid
  end;

  TFlow = record
    Vars: array of TVarInfo;
    Alive: TRoots;       // the local regions created and not released
  end;

  TS17 = class
  private
    FSrc: TVetSource;
    FResolver: TPasResolver;  // borrow: the resolver of the checked module, alive during the check
    FFindings: TVetReport;
    FSeen: specialize TOwned<TStringList>;
    FLines: specialize TOwned<TStringList>;  // name=file for the sources of other units read for // root:
    FRoots: array of TRootInfo;
    FProc: TPasProcedure;     // borrow: the routine being checked
    FDecl: TPasProcedure;     // borrow: its declaration in the interface or a forward one, else nil
    FResultRoots: TRoots;     // the roots a result and a var/out parameter may have
    FBound: TRoots;           // the parameters named by // root: in a routine without a TRegion parameter: they are
                              // in the caller's current region
    FOrder: Integer;
    FExcused: specialize TOwned<TStringList>;  // rows where S5 and S6 of the untyped rules do not apply
    FInferred: specialize TOwned<TStringList>; // routine=",a,b," : what each routine keeps current values in
    FFixes: specialize TOwned<TStringList>;    // row=text to append (--fix)
    FInfer: Boolean;   // the inference passes: no findings, the marks grow
    FLoops: String;    // the loops around the statement being walked (Walk)
    FChanged: Boolean;
    FModule: TPasModule;  // borrow: the module being checked
    function Key(const P: TPasProcedure): String;
    function MarkOf(const P: TPasProcedure): String;
    procedure Grow(const Name: String);
    function Exported(const P: TPasProcedure): Boolean;
    procedure Add(const El: TPasElement; const Msg: String);
    function LineOf(const FileName: String; const Row: Integer): String;
    function Ref(const E: TPasExpr): TPasElement;
    function IsOuterLocal(const D: TPasElement): Boolean;
    function TypeOf(const E: TPasExpr): TPasType;
    function Resolve(const T: TPasElement): TPasType;
    function Alloc(const E: TPasExpr; const F: TFlow): TRoots;
    function Tracked(const E: TPasExpr): Boolean;
    function RootIndex(const Decl: TPasElement): Integer;
    function AddRoot(const AKind: TRootKind; const ADecl: TPasElement; const AName: String): Integer;
    function VarIndex(const F: TFlow; const Decl: TPasElement): Integer;
    function RootNames(const R: TRoots): String;
    function Outlives(const A, B: Integer): Boolean;
    function Current(const F: TFlow): TRoots;
    procedure Kill(var F: TFlow; const Region: Integer; const Release: Boolean);
    function CallRoots(const Callee: TPasProcedure; const Recv: TPasExpr; const Args: array of TPasExpr;
      var F: TFlow; const Where: TPasExpr): TRoots;
    function Eval(const E: TPasExpr; var F: TFlow): TRoots;
    procedure CheckStore(const V, Target: TRoots; const Where: TPasElement; const What: String);
    procedure Store(const L: TPasExpr; const V: TRoots; var F: TFlow);
    procedure Walk(const El: TPasElement; var F: TFlow);
    procedure WalkStmt(const El: TPasElement; var F: TFlow);
    procedure WalkLoop(const Cond: TPasExpr; const Body: TPasElement; var F: TFlow; const Before: Boolean);
    function Join(const A, B: TFlow): TFlow;
    function RootMark(const P: TPasProcedure): String;
    procedure CheckCurrent(const Callee: TPasProcedure; const Name: String; const R: TRoots; const Where: TPasExpr;
      const F: TFlow);
  public
    constructor Create(const ASrc: TVetSource; const AResolver: TPasResolver);
    procedure CheckRoutine(const P: TPasProcedure);
    procedure ReportMissingMarks(const P: TPasProcedure);
    procedure CheckBlock(const Block: TPasImplBlock; const Decls: TPasDeclarations);
    procedure Excuse(const Rule: String; const Row: Integer);
    procedure Flush(var Report: TVetReport);
  end;

  TS17Box = specialize TOwned<TS17>;
  TLinesBox = specialize TOwned<TStringList>;

const
  CallerBit = TRoots(1);
  MaxRoots = 63;

{ The name an element shows in a message: the identifier of a primitive expression. }
function NameOf(const El: TPasElement): String;
begin
  if (El is TBinaryExpr) and (TBinaryExpr(El).OpCode = eopSubIdent) then
    Result := NameOf(TBinaryExpr(El).right)
  else if El is TParamsExpr then
    Result := NameOf(TParamsExpr(El).Value)
  else if El is TPrimitiveExpr then
    Result := TPrimitiveExpr(El).Value
  else if El is TSelfExpr then
    Result := 'Self'
  else
    Result := El.Name;
end;

function Bit(const I: Integer): TRoots;
begin
  Result := TRoots(1) shl I;
end;

function IsRegionRecord(const T: TPasType): Boolean;
begin
  Result := (T is TPasRecordType) and SameText(T.Name, 'TRegion');
end;

function IsGrowArray(const T: TPasType): Boolean;
begin
  Result := (T is TPasRecordType) and SameText(Copy(T.Name, 1, 10), 'TGrowArray');
end;

function IsRegionClass(const T: TPasType): Boolean;
var
  C: TPasType;
begin
  C := T;
  while C is TPasClassType do
  begin
    if SameText(C.Name, 'TRegionObject') then
      Exit(True);
    C := TPasClassType(C).AncestorType;
  end;
  Result := False;
end;

{ A value of the region style: an object of a region class or a TGrowArray. }
function IsRegionValue(const T: TPasType): Boolean;
begin
  Result := IsRegionClass(T) or IsGrowArray(T);
end;

{ ---------- TS17 ---------- }

constructor TS17.Create(const ASrc: TVetSource; const AResolver: TPasResolver);
begin
  inherited Create;
  FSrc := ASrc;
  // borrow: the resolver outlives the check (VetResolve)
  FResolver := AResolver;
  FSeen := specialize TOwned<TStringList>.Own(TStringList.Create);
  FSeen.Get.Sorted := True;
  FLines := specialize TOwned<TStringList>.Own(TStringList.Create);
  FExcused := specialize TOwned<TStringList>.Own(TStringList.Create);
  FExcused.Get.Sorted := True;
  FExcused.Get.Duplicates := dupIgnore;
  FInferred := specialize TOwned<TStringList>.Own(TStringList.Create);
  FFixes := specialize TOwned<TStringList>.Own(TStringList.Create);
end;

{ A routine and its declaration (in the interface, or a forward one) share one entry. }
function TS17.Key(const P: TPasProcedure): String;
var
  D: TPasProcedure;
begin
  D := P;
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    D := TPasProcedureScope(P.CustomData).DeclarationProc;
  Result := IntToHex(PtrUInt(D), 16);
end;

{ The // root: names of P: written on its header or its declaration, and inferred from the bodies of the module.
  "^name" is a local of the enclosing routine that a nested routine keeps current values in. }
function TS17.MarkOf(const P: TPasProcedure): String;
begin
  Result := RootMark(P) + FInferred.Get.Values[Key(P)];
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    Result := Result + RootMark(TPasProcedureScope(P.CustomData).DeclarationProc);
end;

procedure TS17.Grow(const Name: String);
var
  K, Cur: String;
begin
  if not FInfer or (FProc = nil) then
    Exit;
  K := Key(FProc);
  Cur := FInferred.Get.Values[K];
  if Pos(',' + LowerCase(Name) + ',', Cur) > 0 then
    Exit;
  if Cur = '' then
    Cur := ',';
  FInferred.Get.Values[K] := Cur + LowerCase(Name) + ',';
  FChanged := True;
end;

{ P is declared in the interface of the unit (a routine, or a method of a type declared there). }
function TS17.Exported(const P: TPasProcedure): Boolean;
var
  D: TPasElement;
begin
  D := P;
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    D := TPasProcedureScope(P.CustomData).DeclarationProc;
  while (D <> nil) and not (D is TPasSection) do
    D := D.Parent;
  Result := (D <> nil) and (D = FModule.InterfaceSection);
end;

procedure TS17.Excuse(const Rule: String; const Row: Integer);
begin
  FExcused.Get.Add(Format('%s %d', [Rule, Row]));
end;

function TS17.LineOf(const FileName: String; const Row: Integer): String;
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
    FLines.Get.OwnsObjects := True;
    I := FLines.Get.AddObject(FileName + '=', L);
  end;
  L := TStringList(FLines.Get.Objects[I]);
  if (Row >= 1) and (Row <= L.Count) then
    Result := L[Row - 1]
  else
    Result := '';
end;

procedure TS17.Add(const El: TPasElement; const Msg: String);
var
  Row: Integer;
  Seen, Line: String;
begin
  if FInfer then
    Exit;
  Row := El.SourceLinenumber;
  Line := VetLine(FSrc, Row);
  if (Pos('// UNSAFE:', Line) > 0) or (Pos('// UNSAFE:', TrimLeft(VetLine(FSrc, Row - 1))) = 1) then
    Exit;
  Seen := Format('%.6d %s', [Row, Msg]);
  if FSeen.Get.IndexOf(Seen) >= 0 then
    Exit;
  FSeen.Get.Add(Seen);
  VetAdd(FFindings, FSrc.FileName, Row, VetWordColumn(Line, NameOf(El)), vsError, 'S17', Msg);
end;

{ Adds the findings to Report and drops there the findings of S5 and S6 that the region style answers: an object of a
  region class is owned by its region (S6), a field of a region class lives in the same region as its object and a
  store of a value of a region is checked here (S5). }
procedure TS17.Flush(var Report: TVetReport);
var
  I, N, Row: Integer;
  Lines: TLinesBox;
begin
  N := 0;
  for I := 0 to High(Report.Findings) do
    with Report.Findings[I] do
      if not (SameFileName(FileName, FSrc.FileName) and (FExcused.Get.IndexOf(Format('%s %d', [Rule, Row])) >= 0))
        then
      begin
        Report.Findings[N] := Report.Findings[I];
        Inc(N);
      end;
  SetLength(Report.Findings, N);
  if S17Fix and (FFixes.Get.Count > 0) then
  begin
    Lines := TLinesBox.Own(TStringList.Create);
    for I := 0 to High(FSrc.Lines) do
      Lines.Get.Add(FSrc.Lines[I]);
    for I := 0 to FFixes.Get.Count - 1 do
    begin
      Row := StrToInt(FFixes.Get.Names[I]);
      Lines.Get[Row - 1] := Lines.Get[Row - 1] + FFixes.Get.ValueFromIndex[I];
    end;
    Lines.Get.SaveToFile(FSrc.FileName);
  end;
  for I := 0 to High(FFindings.Findings) do
    with FFindings.Findings[I] do
      VetAdd(Report, FileName, Row, Col, Severity, Rule, Msg);
end;

{ What E names; a parameter of the declaration of the routine being checked is the same parameter of its body. }
{ D is a variable or a parameter of a routine that encloses the one being checked. }
function TS17.IsOuterLocal(const D: TPasElement): Boolean;
begin
  Result := ((D is TPasVariable) and (D.Parent is TProcedureBody) or (D is TPasArgument)) and (D.Parent <> nil)
    and (D.Parent <> FProc.Body) and (D.Parent <> FProc.ProcType);
end;

function TS17.Ref(const E: TPasExpr): TPasElement;
var
  I: Integer;
begin
  Result := nil;
  if (E <> nil) and (E.CustomData is TResolvedReference) then
    Result := TResolvedReference(E.CustomData).Declaration;
  if (Result is TPasArgument) and (FDecl <> nil) and (Result.Parent = FDecl.ProcType) then
  begin
    I := FDecl.ProcType.Args.IndexOf(Result);
    if (I >= 0) and (I < FProc.ProcType.Args.Count) then
      Result := TPasElement(FProc.ProcType.Args[I]);
  end;
end;

function TS17.TypeOf(const E: TPasExpr): TPasType;
var
  R: TPasResolverResult;
begin
  Result := nil;
  try
    FResolver.ComputeElement(E, R, []);
    Result := R.LoTypeEl;
  except
    on Exception do
      Result := nil;
  end;
end;

{ The type T denotes, through aliases and specializations; nil when it does not resolve. }
function TS17.Resolve(const T: TPasElement): TPasType;
var
  R: TPasResolverResult;
begin
  Result := nil;
  if T = nil then
    Exit;
  try
    FResolver.ComputeElement(T, R, []);
    Result := R.LoTypeEl;
  except
    on Exception do
      Result := nil;
  end;
end;

{ An allocation of a region object or a TGrowArray in the current region. }
function TS17.Alloc(const E: TPasExpr; const F: TFlow): TRoots;
begin
  Excuse('S6', E.SourceLinenumber);
  Result := Current(F);
end;

{ The value of E can refer to the region style: a class, a record, a pointer or an array; not a number or a string. }
function TS17.Tracked(const E: TPasExpr): Boolean;
var
  T: TPasType;
begin
  T := TypeOf(E);
  Result := (T is TPasClassType) or (T is TPasRecordType) or (T is TPasPointerType) or (T is TPasArrayType)
    or ((T <> nil) and SameText(T.Name, 'Pointer'));
end;

function TS17.RootIndex(const Decl: TPasElement): Integer;
var
  I: Integer;
begin
  for I := 1 to High(FRoots) do
    if FRoots[I].Decl = Decl then
      Exit(I);
  Result := -1;
end;

function TS17.AddRoot(const AKind: TRootKind; const ADecl: TPasElement; const AName: String): Integer;
begin
  Result := Length(FRoots);
  if Result > MaxRoots then
    Exit(0); // too many roots: the extra ones count as the caller's region
  SetLength(FRoots, Result + 1);
  FRoots[Result].Kind := AKind;
  FRoots[Result].Decl := ADecl;
  FRoots[Result].Name := AName;
  FRoots[Result].Order := 0;
end;

function TS17.VarIndex(const F: TFlow; const Decl: TPasElement): Integer;
var
  I: Integer;
begin
  for I := 0 to High(F.Vars) do
    if (F.Vars[I].Decl = Decl) or (Decl is TPasResultElement) and (F.Vars[I].Kind = vkResult) then
      Exit(I);
  Result := -1;
end;

function TS17.RootNames(const R: TRoots): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FRoots) do
    if R and Bit(I) <> 0 then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + FRoots[I].Name;
    end;
end;

{ The root A lives at least as long as the root B. }
function TS17.Outlives(const A, B: Integer): Boolean;
begin
  if (A = B) or (FBound <> 0) and ((FBound or CallerBit) and Bit(A) <> 0) and ((FBound or CallerBit) and Bit(B) <> 0)
    then
    Exit(True); // the caller's current region and what // root: names are one region
  case FRoots[B].Kind of
    rkRegion:
      Result := (FRoots[A].Kind <> rkRegion) or (FRoots[A].Order < FRoots[B].Order);
    rkCaller:
      Result := FRoots[A].Kind = rkParam;
    rkParam:
      Result := False; // two parameters: unknown regions of the caller
  end;
end;

{ Where an allocation without a region argument goes: the innermost live region of the routine, else the caller's. }
function TS17.Current(const F: TFlow): TRoots;
var
  I, Best: Integer;
begin
  Best := -1;
  for I := 1 to High(FRoots) do
    if (FRoots[I].Kind = rkRegion) and (F.Alive and Bit(I) <> 0)
      and ((Best < 0) or (FRoots[I].Order > FRoots[Best].Order)) then
      Best := I;
  if Best < 0 then
    Result := CallerBit
  else
    Result := Bit(Best);
end;

{ Reset or Release of the local region Region: what it and the regions created after it hold is freed. }
procedure TS17.Kill(var F: TFlow; const Region: Integer; const Release: Boolean);
var
  I: Integer;
  Freed: TRoots;
  What: String;
begin
  if Release then
    What := FRoots[Region].Name + '.Release'
  else
    What := FRoots[Region].Name + '.Reset';
  Freed := Bit(Region);
  for I := 1 to High(FRoots) do
    if (FRoots[I].Kind = rkRegion) and (F.Alive and Bit(I) <> 0) and (FRoots[I].Order > FRoots[Region].Order) then
      Freed := Freed or Bit(I);
  for I := 0 to High(F.Vars) do
    if (F.Vars[I].Roots and Freed <> 0) and (F.Vars[I].Dead = '') then
      F.Vars[I].Dead := What;
  if Release then
    F.Alive := F.Alive and not Bit(Region);
end;

{ The names of "// root: A, B" on the header line of P as ",a,b,"; '' without the mark. }
function TS17.RootMark(const P: TPasProcedure): String;
var
  Line: String;
  I, J: Integer;
begin
  Result := '';
  Line := LineOf(P.SourceFilename, P.SourceLinenumber);
  I := Pos('// root:', Line);
  if I = 0 then
    Exit;
  Inc(I, 8);
  repeat
    while (I <= Length(Line)) and (Line[I] = ' ') do
      Inc(I);
    J := I;
    while (I <= Length(Line)) and (Line[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      Inc(I);
    if I = J then
      Break;
    Result := Result + ',' + LowerCase(Copy(Line, J, I - J));
    while (I <= Length(Line)) and (Line[I] = ' ') do
      Inc(I);
    if (I > Length(Line)) or (Line[I] <> ',') then
      Break;
    Inc(I);
  until False;
  if Result <> '' then
    Result := Result + ',';
end;

function InMark(const Mark, Name: String): Boolean;
begin
  Result := Pos(',' + LowerCase(Name) + ',', Mark) > 0;
end;

{ A routine marked "// root: P" keeps values of the current region in P: at the call, P must be in that region. }
procedure TS17.CheckCurrent(const Callee: TPasProcedure; const Name: String; const R: TRoots; const Where: TPasExpr;
  const F: TFlow);
var
  A, C: Integer;
begin
  C := 0;
  for A := 1 to High(FRoots) do
    if Current(F) = Bit(A) then
      C := A;
  for A := 0 to High(FRoots) do
    if (R and Bit(A) <> 0) and not Outlives(C, A) and FInfer and (C = 0) and (FRoots[A].Kind = rkParam) then
      Grow(FRoots[A].Name)
    else if (R and Bit(A) <> 0) and not Outlives(C, A) then
    begin
      Add(Where, Format('%s keeps values of the current region in %s (// root: %s), but %s is in %s, not in the '
        + 'current region %s (rule 4): call it while %s is the current region', [Callee.Name, Name, Name,
        NameOf(Where), FRoots[A].Name, FRoots[C].Name, FRoots[A].Name]));
      Exit;
    end;
end;

{ The roots of a call of Callee (on Recv, if a method) with Args, and its effects on the flow. }
function TS17.CallRoots(const Callee: TPasProcedure; const Recv: TPasExpr; const Args: array of TPasExpr;
  var F: TFlow; const Where: TPasExpr): TRoots;
var
  I, N, K, Regions: Integer;
  ArgRoots: array of TRoots;
  RecvRoots, RegionArgs, Named: TRoots;
  RecvType, OwnerType: TPasType;
  Formal: TPasArgument;
  Mark, Name: String;
begin
  Result := 0;
  RecvRoots := 0;
  RecvType := nil;
  if Recv <> nil then
  begin
    RecvType := TypeOf(Recv);
    RecvRoots := Eval(Recv, F);
  end;
  SetLength(ArgRoots, Length(Args));
  for I := 0 to High(Args) do
    ArgRoots[I] := Eval(Args[I], F);
  if Callee = nil then
    Exit;
  Name := LowerCase(Callee.Name);
  OwnerType := nil;
  if Callee.Parent is TPasType then
    OwnerType := TPasType(Callee.Parent);
  // a region: Create, Reset, Release (Create is handled by the assignment)
  if IsRegionRecord(RecvType) and (Recv is TPrimitiveExpr) then
  begin
    K := RootIndex(Ref(Recv));
    if (K > 0) and (FRoots[K].Kind = rkRegion) and ((Name = 'reset') or (Name = 'release')) then
      Kill(F, K, Name = 'release');
    Exit;
  end;
  // a TGrowArray: Push and SetItem store into it, At and GetItem read from it, Create allocates
  if IsGrowArray(OwnerType) then
  begin
    if (Name = 'push') or (Name = 'setitem') then
      for I := 0 to High(Args) do
        CheckStore(ArgRoots[I], RecvRoots, Where, 'an element of ' + RootNames(RecvRoots));
    if (Name = 'at') or (Name = 'getitem') or (Name = 'toarray') or (Name = 'getenumerator') then
      Exit(RecvRoots);
    if Name <> 'create' then
      Exit(0);
  end;
  // a method of an object of another style may keep what it gets
  if (RecvType is TPasClassType) and not IsRegionClass(RecvType) then
    for I := 0 to High(Args) do
      if ArgRoots[I] <> 0 then
        Add(Args[I], 'a value of a region is passed to a method of an object of another style, which may keep it: '
          + 'pass a copy (a String, a record) or keep the object in the region');
  // a channel
  if (OwnerType <> nil) and SameText(Copy(OwnerType.Name, 1, 5), 'TChan') and (Name = 'send') then
    for I := 0 to High(Args) do
      if ArgRoots[I] <> 0 then
        Add(Args[I], 'a value of a region is sent to a channel: it leaves its goroutine; send a copy (a record, a '
          + 'String) instead (S18)');
  // var and out arguments get a value the callee may have allocated in the current region
  N := Callee.ProcType.Args.Count;
  Regions := 0;
  RegionArgs := 0;
  Named := 0;
  Mark := MarkOf(Callee);
  for I := 0 to N - 1 do
  begin
    Formal := TPasArgument(Callee.ProcType.Args[I]);
    if I > High(Args) then
      Break;
    if IsRegionRecord(Resolve(Formal.ArgType)) then
    begin
      Inc(Regions);
      RegionArgs := RegionArgs or ArgRoots[I];
      if InMark(Mark, Formal.Name) then
        Named := ArgRoots[I];
    end
    else if (Formal.Access in [argVar, argOut]) and not (Args[I] is TPrimitiveExpr) and Tracked(Args[I]) then
      Store(Args[I], Current(F), F) // a field gets a value the callee may have allocated in the current region
    else if (Formal.Access in [argVar, argOut]) and (Args[I] is TPrimitiveExpr) then
    begin
      K := VarIndex(F, Ref(Args[I]));
      if (K >= 0) and Tracked(Args[I]) then
      begin
        F.Vars[K].Roots := Current(F);
        F.Vars[K].Dead := '';
      end;
    end;
  end;
  // // root: P without region parameters: P is in the current region
  if (Regions = 0) and (Mark <> '') then
  begin
    for I := 0 to Min(N, Length(Args)) - 1 do
      if InMark(Mark, TPasArgument(Callee.ProcType.Args[I]).Name) then
        CheckCurrent(Callee, TPasArgument(Callee.ProcType.Args[I]).Name, ArgRoots[I], Args[I], F);
    if InMark(Mark, 'Self') then
    begin
      if (Recv = nil) and (RootIndex(FProc) > 0) then
        RecvRoots := Bit(RootIndex(FProc));
      CheckCurrent(Callee, 'Self', RecvRoots, Where, F);
    end;
  end;
  // a nested routine keeps values of the current region in locals of the routine it is in (this one)
  if Pos(',^', Mark) > 0 then
    for K := 0 to High(F.Vars) do
      if InMark(Mark, '^' + F.Vars[K].Decl.Name) then
        F.Vars[K].Roots := F.Vars[K].Roots or Current(F);
  // the result (rule 4)
  if (Callee is TPasConstructor) or (Callee.ProcType is TPasFunctionType) then
  begin
    if Regions = 1 then
      Result := RegionArgs
    else if (Regions > 1) and (Named <> 0) then
      Result := Named
    else if Regions > 1 then
      Result := RegionArgs
    else
      Result := Current(F);
  end;
end;

function TS17.Eval(const E: TPasExpr; var F: TFlow): TRoots;
var
  D: TPasElement;
  K, I: Integer;
  B: TBinaryExpr;
  P: TParamsExpr;
  Recv: TPasExpr;
  Args: array of TPasExpr;
begin
  Result := 0;
  if E = nil then
    Exit;
  if E is TPrimitiveExpr then
  begin
    D := Ref(E);
    if D is TPasProcedure then
      Result := CallRoots(TPasProcedure(D), nil, [], F, E)
    else
    begin
      K := VarIndex(F, D);
      if K >= 0 then
      begin
        if F.Vars[K].Dead <> '' then
        begin
          Add(E, Format('%s is used after %s, which freed what it refers to (rule 3): use it before, or assign it '
            + 'again after', [NameOf(E), F.Vars[K].Dead]));
          F.Vars[K].Dead := ''; // one finding per use after a free
        end;
        Result := F.Vars[K].Roots;
      end
      else if (D is TPasVariable) and (D.Parent is TPasClassType) and (FProc <> nil) then
      begin
        // a field through the implicit Self
        K := RootIndex(FProc);
        if K > 0 then
          Result := Bit(K);
      end
      else if IsOuterLocal(D) then
        Result := CallerBit; // a local of the enclosing routine lives at least as long as this call
    end;
  end
  else if E is TSelfExpr then
  begin
    K := RootIndex(FProc);
    if K > 0 then
      Result := Bit(K);
  end
  else if (E is TBinaryExpr) and (TBinaryExpr(E).OpCode = eopSubIdent) then
  begin
    B := TBinaryExpr(E);
    D := Ref(B.right);
    if (D is TPasProcedure) and (B.right is TPrimitiveExpr) then
    begin
      if Ref(B.left) is TPasType then
      begin
        if IsRegionValue(Resolve(Ref(B.left))) and SameText(D.Name, 'Create') then
          Result := Alloc(E, F)
        else
          Result := CallRoots(TPasProcedure(D), nil, [], F, E);
      end
      else if Ref(B.left) is TPasModule then
        Result := CallRoots(TPasProcedure(D), nil, [], F, E)
      else
        Result := CallRoots(TPasProcedure(D), B.left, [], F, E);
    end
    else if B.right is TParamsExpr then
      Result := Eval(B.right, F) // A.B(...) is a TParamsExpr with the value A.B
    else
      Result := Eval(B.left, F); // a field: in the region of its object
  end
  else if E is TBinaryExpr then
  begin
    Eval(TBinaryExpr(E).left, F);
    Eval(TBinaryExpr(E).right, F);
  end
  else if (E is TUnaryExpr) and (TUnaryExpr(E).OpCode = eopAddress) and (Ref(TUnaryExpr(E).Operand) is TPasProcedure)
    then
  begin
    if Pos(',^', MarkOf(TPasProcedure(Ref(TUnaryExpr(E).Operand)))) > 0 then
      Add(TUnaryExpr(E).Operand, Format('%s keeps values of the current region in locals of the routine it is in; as '
        + 'a procedure value it may run while another region is current: call it directly (rule 1)',
        [NameOf(TUnaryExpr(E).Operand)]));
  end
  else if E is TUnaryExpr then
    Result := Eval(TUnaryExpr(E).Operand, F)
  else if E is TParamsExpr then
  begin
    P := TParamsExpr(E);
    SetLength(Args, Length(P.Params));
    for I := 0 to High(P.Params) do
      Args[I] := P.Params[I];
    Recv := nil;
    if (P.Value is TBinaryExpr) and (TBinaryExpr(P.Value).OpCode = eopSubIdent) then
    begin
      D := Ref(TBinaryExpr(P.Value).right);
      Recv := TBinaryExpr(P.Value).left;
    end
    else
      D := Ref(P.Value);
    if P.Kind = pekArrayParams then
    begin
      for I := 0 to High(Args) do
        Eval(Args[I], F);
      Result := Eval(P.Value, F); // A[I]: in the region of A
    end
    else if D is TPasType then
    begin
      // a type cast keeps the roots
      for I := 0 to High(Args) do
        Result := Result or Eval(Args[I], F);
    end
    else if D is TPasProcedure then
    begin
      if (Recv <> nil) and (Ref(Recv) is TPasType) and IsRegionValue(Resolve(Ref(Recv)))
        and SameText(D.Name, 'Create') then
      begin
        for I := 0 to High(Args) do
          Eval(Args[I], F);
        Result := Alloc(E, F);
      end
      else if (Recv <> nil) and ((Ref(Recv) is TPasType) or (Ref(Recv) is TPasModule)) then
        Result := CallRoots(TPasProcedure(D), nil, Args, F, E)
      else
        Result := CallRoots(TPasProcedure(D), Recv, Args, F, E);
    end
    else
    begin
      Eval(P.Value, F);
      for I := 0 to High(Args) do
        Eval(Args[I], F);
    end;
  end;
  if (Result <> 0) and not Tracked(E) then
    Result := 0;
end;

procedure TS17.CheckStore(const V, Target: TRoots; const Where: TPasElement; const What: String);
var
  A, B: Integer;
begin
  if (V = 0) or (Target = 0) then
    Exit;
  Excuse('S5', Where.SourceLinenumber); // the escape of a borrow (S5) is this check for a value of a region
  for A := 0 to High(FRoots) do
    if V and Bit(A) <> 0 then
      for B := 0 to High(FRoots) do
        if (Target and Bit(B) <> 0) and not Outlives(A, B) then
        begin
          if (FRoots[A].Kind <> rkRegion) and (FRoots[B].Kind = rkParam) and FInfer then
          begin
            Grow(FRoots[B].Name);
            if FRoots[A].Kind = rkParam then
              Grow(FRoots[A].Name);
            Continue;
          end
          else if (FRoots[A].Kind <> rkRegion) and (FRoots[B].Kind = rkParam) then
            Add(Where, Format('a value of %s is stored into %s, which may outlive it (rule 1): if the callers keep '
              + 'them in their current region, say so with // root: %s on the header line (rule 4)',
              [FRoots[A].Name, What, Trim(StringReplace(FRoots[B].Name + ', ' + FRoots[A].Name,
              ', the caller''s region', '', []))]))
          else
            Add(Where, Format('a value of %s is stored into %s, which may outlive it (rule 1): allocate it in the '
              + 'region of the target, or keep the target in %s', [FRoots[A].Name, What, FRoots[A].Name]));
          Exit;
        end;
end;

{ L := (a value with the roots V) }
procedure TS17.Store(const L: TPasExpr; const V: TRoots; var F: TFlow);
var
  D: TPasElement;
  K: Integer;
  Base: TPasExpr;
  T: TPasType;
  Bad: TRoots;
begin
  if L is TPrimitiveExpr then
  begin
    D := Ref(L);
    K := VarIndex(F, D);
    if K >= 0 then
    begin
      case F.Vars[K].Kind of
        vkLocal:
          ;
        vkResult, vkByRef, vkOuter:
          begin
            Bad := V and not FResultRoots;
            if Bad <> 0 then
              Add(L, Format('%s gets a value of %s, which is freed when the routine returns (rules 1, 4): '
                + 'allocate it in the caller''s region (a routine without a TRegion, or the region parameter)',
                [NameOf(L), RootNames(Bad)]));
          end;
      end;
      F.Vars[K].Roots := V;
      F.Vars[K].Dead := '';
    end
    else if (D is TPasVariable) and (D.Parent is TPasClassType) then
    begin
      // a field through the implicit Self
      K := RootIndex(FProc);
      if K > 0 then
        CheckStore(V, Bit(K), L, 'a field of Self')
      else if V <> 0 then
        Add(L, Format('a value of %s is stored into a field of an object of another style (rule 2): keep a copy, '
          + 'or make the class a TRegionObject', [RootNames(V)]));
    end
    else if IsOuterLocal(D) then
    begin
      // a local of the enclosing routine: as a var parameter; each call sets its roots (CallRoots)
      if V <> 0 then
        Grow('^' + D.Name);
      Bad := V and not FResultRoots;
      if Bad <> 0 then
        Add(L, Format('%s of the enclosing routine gets a value of %s, which is freed when this routine returns '
          + '(rules 1, 4): allocate it in the caller''s region', [NameOf(L), RootNames(Bad)]));
    end
    else if (D is TPasVariable) and (V <> 0) then
      Add(L, Format('a value of %s is stored into the global %s (rule 2): a global outlives every region; keep it '
        + 'in a local or in an object of the same region', [RootNames(V), NameOf(L)]));
    Exit;
  end;
  // a field or an element: L = X.F, X[I], X.At(I).F
  if (L is TBinaryExpr) and (TBinaryExpr(L).OpCode = eopSubIdent) then
    Base := TBinaryExpr(L).left
  else if L is TParamsExpr then
  begin
    for K := 0 to High(TParamsExpr(L).Params) do
      Eval(TParamsExpr(L).Params[K], F);
    Base := TParamsExpr(L).Value;
    if IsGrowArray(TypeOf(Base)) then
    begin
      CheckStore(V, Eval(Base, F), L, 'an element of ' + RootNames(Eval(Base, F)));
      Exit;
    end;
  end
  else
    Exit;
  T := TypeOf(Base);
  if (T is TPasRecordType) and not IsGrowArray(T) and (Base is TPrimitiveExpr) then
  begin
    // a field of a local record: the record holds the roots
    K := VarIndex(F, Ref(Base));
    if K >= 0 then
    begin
      if F.Vars[K].Kind <> vkLocal then
        Store(Base, V or F.Vars[K].Roots, F)
      else
        F.Vars[K].Roots := F.Vars[K].Roots or V;
      Exit;
    end;
  end;
  if IsRegionValue(T) or (T is TPasPointerType) or (T is TPasRecordType) then
  begin
    K := 0;
    Bad := Eval(Base, F);
    if Bad <> 0 then
      CheckStore(V, Bad, L, 'an object of ' + RootNames(Bad))
    else if (V <> 0) and not (T is TPasRecordType) then
      Add(L, Format('a value of %s is stored where its root is not known (rule 5): keep it in an object of %s',
        [RootNames(V), RootNames(V)]));
  end
  else
  begin
    Eval(Base, F);
    if V <> 0 then
      Add(L, Format('a value of %s is stored into a field of an object of another style (rule 2): keep a copy, or '
        + 'make the class a TRegionObject', [RootNames(V)]));
  end;
end;

function TS17.Join(const A, B: TFlow): TFlow;
var
  I: Integer;
begin
  Result := A;
  SetLength(Result.Vars, Length(A.Vars));
  for I := 0 to High(A.Vars) do
  begin
    Result.Vars[I] := A.Vars[I];
    Result.Vars[I].Roots := A.Vars[I].Roots or B.Vars[I].Roots;
    if Result.Vars[I].Dead = '' then
      Result.Vars[I].Dead := B.Vars[I].Dead;
  end;
  Result.Alive := A.Alive or B.Alive;
end;

{ A loop: the body twice, the second time from the join of the entry and the end of the first pass. }
procedure TS17.WalkLoop(const Cond: TPasExpr; const Body: TPasElement; var F: TFlow; const Before: Boolean);
var
  Pass: Integer;
  B: TFlow;
begin
  for Pass := 1 to 2 do
  begin
    B := F;
    SetLength(B.Vars, Length(F.Vars));
    if Before then
      Eval(Cond, B);
    Walk(Body, B);
    if not Before then
      Eval(Cond, B);
    F := Join(F, B);
  end;
end;

{ The loops around the statement: 'S' a region loop (for R in Scope, for X in Each(...)), 'L' another loop. A Break
  out of a region loop releases its region late, out of order with a TRegion created after it (R14): an error. }
procedure TS17.Walk(const El: TPasElement; var F: TFlow);
var
  T: TPasType;
  K: Char;
begin
  K := #0;
  if (El is TPasImplForLoop) and (TPasImplForLoop(El).LoopType = ltIn) then
  begin
    T := TypeOf(TPasImplForLoop(El).StartExpr);
    if (T <> nil) and (SameText(T.Name, 'TScopes') or SameText(Copy(T.Name, 1, 5), 'TEach')) then
      K := 'S'
    else
      K := 'L';
  end
  else if (El is TPasImplForLoop) or (El is TPasImplWhileDo) or (El is TPasImplRepeatUntil) then
    K := 'L';
  if (El is TPasImplSimple) and (TPasImplSimple(El).expr is TPrimitiveExpr)
    and SameText(NameOf(TPasImplSimple(El).expr), 'Break') and (FLoops <> '') and (FLoops[Length(FLoops)] = 'S') then
    Add(TPasImplSimple(El).expr, 'Break out of a region loop (for ... in Scope or Each): its region would be released '
      + 'late, out of order (R14); leave with Exit, or end the loop by its condition');
  if K <> #0 then
    FLoops := FLoops + K;
  WalkStmt(El, F);
  if K <> #0 then
    SetLength(FLoops, Length(FLoops) - 1);
end;

procedure TS17.WalkStmt(const El: TPasElement; var F: TFlow);
var
  I, K: Integer;
  A: TPasImplAssign;
  C: TPasImplIfElse;
  L: TPasImplForLoop;
  T: TPasImplTry;
  Cs: TPasImplCaseOf;
  F1, F2, Start: TFlow;
  V: TRoots;
  HasElse: Boolean;
begin
  if El = nil then
    Exit;
  if El is TPasImplAssign then
  begin
    A := TPasImplAssign(El);
    K := RootIndex(Ref(A.left));
    if (K > 0) and (FRoots[K].Kind = rkRegion) then
    begin
      // R := TRegion.Create: a new region; the old one, if alive, is released; the variable owns it (S6)
      Excuse('S6', A.SourceLinenumber);
      Eval(A.right, F);
      if F.Alive and Bit(K) <> 0 then
        Kill(F, K, False);
      Inc(FOrder);
      FRoots[K].Order := FOrder;
      F.Alive := F.Alive or Bit(K);
      Exit;
    end;
    V := Eval(A.right, F);
    Store(A.left, V, F);
  end
  else if El is TPasImplSimple then
    Eval(TPasImplSimple(El).expr, F)
  else if El is TPasImplIfElse then
  begin
    C := TPasImplIfElse(El);
    Eval(C.ConditionExpr, F);
    F1 := F;
    SetLength(F1.Vars, Length(F.Vars));
    F2 := F;
    SetLength(F2.Vars, Length(F.Vars));
    Walk(C.IfBranch, F1);
    Walk(C.ElseBranch, F2);
    F := Join(F1, F2);
  end
  else if El is TPasImplWhileDo then
    WalkLoop(TPasImplWhileDo(El).ConditionExpr, TPasImplWhileDo(El).Body, F, True)
  else if El is TPasImplForLoop then
  begin
    L := TPasImplForLoop(El);
    V := Eval(L.StartExpr, F);
    Eval(L.EndExpr, F);
    K := VarIndex(F, Ref(L.VariableName));
    if (L.LoopType = ltIn) and (K >= 0) then
    begin
      F.Vars[K].Roots := V;
      F.Vars[K].Dead := '';
    end;
    WalkLoop(nil, L.Body, F, True);
  end
  else if El is TPasImplRepeatUntil then
  begin
    for I := 0 to TPasImplBlock(El).Elements.Count - 1 do
      Walk(TPasElement(TPasImplBlock(El).Elements[I]), F);
    Eval(TPasImplRepeatUntil(El).ConditionExpr, F);
    Start := F;
    SetLength(Start.Vars, Length(F.Vars));
    for I := 0 to TPasImplBlock(El).Elements.Count - 1 do
      Walk(TPasElement(TPasImplBlock(El).Elements[I]), Start);
    Eval(TPasImplRepeatUntil(El).ConditionExpr, Start);
    F := Join(F, Start);
  end
  else if El is TPasImplTry then
  begin
    T := TPasImplTry(El);
    Start := F;
    SetLength(Start.Vars, Length(F.Vars));
    for I := 0 to T.Elements.Count - 1 do
      Walk(TPasElement(T.Elements[I]), F);
    if T.FinallyExcept <> nil then
    begin
      // the handler may start at any point of the block
      F1 := Join(Start, F);
      for I := 0 to T.FinallyExcept.Elements.Count - 1 do
        Walk(TPasElement(T.FinallyExcept.Elements[I]), F1);
      if T.FinallyExcept is TPasImplTryFinally then
        F := Join(F, F1)
      else
        F := Join(F, F1);
    end;
  end
  else if El is TPasImplCaseOf then
  begin
    Cs := TPasImplCaseOf(El);
    Eval(Cs.CaseExpr, F);
    Start := F;
    SetLength(Start.Vars, Length(F.Vars));
    HasElse := False;
    for I := 0 to Cs.Elements.Count - 1 do
    begin
      F1 := Start;
      SetLength(F1.Vars, Length(Start.Vars));
      if TObject(Cs.Elements[I]) is TPasImplCaseStatement then
        Walk(TPasImplCaseStatement(Cs.Elements[I]).Body, F1)
      else
      begin
        HasElse := True;
        Walk(TPasElement(Cs.Elements[I]), F1);
      end;
      if I = 0 then
        F := F1
      else
        F := Join(F, F1);
    end;
    if not HasElse then
      F := Join(F, Start);
  end
  else if El is TPasImplExceptOn then
    Walk(TPasImplExceptOn(El).Body, F)
  else if El is TPasImplWithDo then
  begin
    for I := 0 to TPasImplWithDo(El).Expressions.Count - 1 do
      Eval(TPasExpr(TPasImplWithDo(El).Expressions[I]), F);
    Walk(TPasImplWithDo(El).Body, F);
  end
  else if El is TPasImplRaise then
    Eval(TPasImplRaise(El).ExceptObject, F)
  else if El is TPasImplBlock then
    for I := 0 to TPasImplBlock(El).Elements.Count - 1 do
      Walk(TPasElement(TPasImplBlock(El).Elements[I]), F);
end;

procedure TS17.CheckBlock(const Block: TPasImplBlock; const Decls: TPasDeclarations);
var
  F: TFlow;
  I, K: Integer;
  D: TPasElement;
  T: TPasType;
begin
  F := Default(TFlow);
  if Decls <> nil then
    for I := 0 to Decls.Declarations.Count - 1 do
    begin
      D := TPasElement(Decls.Declarations[I]);
      if not (D is TPasVariable) or (D is TPasConst) then
        Continue;
      T := Resolve(TPasVariable(D).VarType);
      if IsRegionRecord(T) then
        AddRoot(rkRegion, D, D.Name) // not created yet: Order 0
      else
      begin
        K := Length(F.Vars);
        SetLength(F.Vars, K + 1);
        F.Vars[K].Decl := D;
        F.Vars[K].Kind := vkLocal;
        F.Vars[K].Roots := 0;
        F.Vars[K].Dead := '';
      end;
    end;
  if FProc <> nil then
  begin
    for I := 0 to FProc.ProcType.Args.Count - 1 do
    begin
      D := TPasElement(FProc.ProcType.Args[I]);
      K := Length(F.Vars);
      SetLength(F.Vars, K + 1);
      F.Vars[K].Decl := D;
      F.Vars[K].Dead := '';
      F.Vars[K].Roots := 0;
      if TPasArgument(D).Access in [argVar, argOut] then
        F.Vars[K].Kind := vkByRef
      else
        F.Vars[K].Kind := vkLocal;
      K := RootIndex(D);
      if K > 0 then
        F.Vars[High(F.Vars)].Roots := Bit(K);
    end;
    if FProc.ProcType is TPasFunctionType then
    begin
      K := Length(F.Vars);
      SetLength(F.Vars, K + 1);
      F.Vars[K].Decl := TPasFunctionType(FProc.ProcType).ResultEl;
      F.Vars[K].Kind := vkResult;
      F.Vars[K].Roots := 0;
      F.Vars[K].Dead := '';
    end;
  end;
  Walk(Block, F);
end;

procedure TS17.CheckRoutine(const P: TPasProcedure);
var
  I, K, Regions: Integer;
  A: TPasArgument;
  T: TPasType;
  Scope: TPasProcedureScope;
  Mark, Written: String;
  Named: Integer;
begin
  if (P.Body = nil) or (P.Body.Body = nil) then
    Exit;
  // borrow: the routine belongs to the module being checked
  FProc := P;
  SetLength(FRoots, 1);
  FRoots[0].Kind := rkCaller;
  FRoots[0].Decl := nil;
  FRoots[0].Name := 'the caller''s region';
  FOrder := 0;
  FResultRoots := CallerBit;
  FBound := 0;
  Regions := 0;
  Named := -1;
  Mark := MarkOf(P);
  FDecl := nil;
  if P.CustomData is TPasProcedureScope then
    // borrow: the declaration belongs to the module being checked
    FDecl := TPasProcedureScope(P.CustomData).DeclarationProc;
  // Self of a method of a region class
  if P.CustomData is TPasProcedureScope then
  begin
    Scope := TPasProcedureScope(P.CustomData);
    if (Scope.ClassRecScope <> nil) and (Scope.ClassRecScope.Element is TPasType)
      and IsRegionValue(TPasType(Scope.ClassRecScope.Element)) then
    begin
      K := AddRoot(rkParam, P, 'Self');
      FResultRoots := FResultRoots or Bit(K);
    end;
  end;
  for I := 0 to P.ProcType.Args.Count - 1 do
  begin
    A := TPasArgument(P.ProcType.Args[I]);
    T := Resolve(A.ArgType);
    if IsRegionRecord(T) then
    begin
      Inc(Regions);
      K := AddRoot(rkParam, A, A.Name);
      if InMark(Mark, A.Name) then
        Named := K;
    end
    else if IsRegionValue(T) then
    begin
      K := AddRoot(rkParam, A, A.Name);
      FResultRoots := FResultRoots or Bit(K);
    end;
  end;
  // // root: P without region parameters: P (or Self) is in the caller's current region
  if (Regions = 0) and (Mark <> '') then
  begin
    for K := 1 to High(FRoots) do
      if InMark(Mark, FRoots[K].Name) then
        FBound := FBound or Bit(K);
    Written := RootMark(P);
    if FDecl <> nil then
      Written := Written + RootMark(FDecl);
    Named := 0;
    for K := 1 to High(FRoots) do
      if InMark(Written, FRoots[K].Name) then
        Inc(Named);
    if (Written <> '') and (Named = 0) then
      Add(P, Format('// root: of %s names no region object among its parameters (or Self of a region class)',
        [P.Name]));
  end;
  // rule 4: with region parameters the result is rooted in one of them
  if Regions = 1 then
    for K := 1 to High(FRoots) do
      if (FRoots[K].Decl is TPasArgument) and IsRegionRecord(Resolve(TPasArgument(FRoots[K].Decl).ArgType)) then
        FResultRoots := Bit(K);
  if Regions > 1 then
  begin
    if Named > 0 then
      FResultRoots := Bit(Named)
    else if P.ProcType is TPasFunctionType then
      Add(P, Format('%s takes %d regions: name the root of its result with // root: <parameter> on its header line '
        + '(rule 4)', [P.Name, Regions]));
  end;
  CheckBlock(P.Body.Body, P.Body);
  if not FInfer and Exported(P) then
    ReportMissingMarks(P);
  FProc := nil;
end;

{ An exported routine shows its // root: names on its declaration: they are a contract for the units that call it. }
procedure TS17.ReportMissingMarks(const P: TPasProcedure);
var
  Written, Inferred, Missing, N: String;
  D: TPasProcedure;
  I: Integer;
begin
  D := P;
  if FDecl <> nil then
    D := FDecl;
  Written := RootMark(D) + RootMark(P);
  Inferred := FInferred.Get.Values[Key(P)];
  Missing := '';
  for N in Inferred.Split([','], TStringSplitOptions.ExcludeEmpty) do
    if (N[1] <> '^') and not InMark(Written, N) then
    begin
      if Missing <> '' then
        Missing := Missing + ', ';
      // the name as it is written in the declaration
      if N = 'self' then
        Missing := Missing + 'Self'
      else
        for I := 0 to D.ProcType.Args.Count - 1 do
          if SameText(TPasArgument(D.ProcType.Args[I]).Name, N) then
            Missing := Missing + TPasArgument(D.ProcType.Args[I]).Name;
    end;
  if Missing = '' then
    Exit;
  if (D.SourceFilename = '') or SameFileName(ExpandFileName(D.SourceFilename), ExpandFileName(FSrc.FileName)) then
  begin
    Add(D, Format('%s keeps values of the caller''s current region in %s: an exported routine says so with '
      + '// root: %s on its header line (bpvet --fix writes it; rule 4)', [D.Name, Missing, Missing]));
    if Written = '' then
      FFixes.Get.Add(IntToStr(D.SourceLinenumber) + '=  // root: ' + Missing)
    else
      FFixes.Get.Add(IntToStr(D.SourceLinenumber) + '=, ' + Missing);
  end;
end;

procedure ExcuseFields(const S: TS17; const C: TPasClassType);
var
  I: Integer;
begin
  for I := 0 to C.Members.Count - 1 do
    if TObject(C.Members[I]) is TPasVariable then
      S.Excuse('S5', TPasElement(C.Members[I]).SourceLinenumber);
end;

{ A TRegion is a local of a routine: its scope is the scope of the region (SPEC §20, concept v2). }
procedure NotLocal(const S: TS17; const V: TPasElement; const T: TPasType; const Where: String);
begin
  if IsRegionRecord(S.Resolve(T)) then
    S.Add(V, Format('a TRegion %s: a region is a local of a routine, released when the routine returns; keep an '
      + 'object that lives longer in the owner or the GC style', [Where]));
end;

procedure CheckMembers(const S: TS17; const T: TPasMembersType);
var
  I: Integer;
begin
  for I := 0 to T.Members.Count - 1 do
    if TObject(T.Members[I]) is TPasVariable then
      NotLocal(S, TPasElement(T.Members[I]), TPasVariable(T.Members[I]).VarType, 'field of ' + T.Name);
end;

procedure CheckDecls(const S: TS17; const Decls: TPasDeclarations; const Top: Boolean);
var
  I: Integer;
  D: TPasElement;
begin
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    D := TPasElement(Decls.Declarations[I]);
    if (D is TPasClassType) and IsRegionClass(TPasClassType(D)) then
      ExcuseFields(S, TPasClassType(D));
    if (D is TPasMembersType) and not S.FInfer then
      CheckMembers(S, TPasMembersType(D))
    else if Top and (D is TPasVariable) and not (D is TPasConst) and not S.FInfer then
      NotLocal(S, D, TPasVariable(D).VarType, 'global')
    else if D is TPasProcedure then
    begin
      S.CheckRoutine(TPasProcedure(D));
      if TPasProcedure(D).Body <> nil then
        CheckDecls(S, TPasProcedure(D).Body, False); // nested routines
    end;
  end;
end;

procedure VetCheckS17(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);
var
  S: TS17Box;
  Pass: Integer;
begin
  S := TS17Box.Own(TS17.Create(Src, Resolver));
  // borrow: the module outlives the check
  S.Get.FModule := Module;
  // the inference: the // root: names of the routines grow until no body adds one
  S.Get.FInfer := True;
  Pass := 0;
  repeat
    S.Get.FChanged := False;
    CheckDecls(S.Get, Module.InterfaceSection, True);
    CheckDecls(S.Get, Module.ImplementationSection, True);
    if Module is TPasProgram then
      CheckDecls(S.Get, TPasProgram(Module).ProgramSection, True);
    Inc(Pass);
  until not S.Get.FChanged or (Pass >= 16);
  S.Get.FInfer := False;
  CheckDecls(S.Get, Module.InterfaceSection, True);
  CheckDecls(S.Get, Module.ImplementationSection, True);
  if Module is TPasProgram then
  begin
    CheckDecls(S.Get, TPasProgram(Module).ProgramSection, True);
    if Module.InitializationSection <> nil then
    begin
      SetLength(S.Get.FRoots, 1);
      S.Get.FRoots[0].Kind := rkCaller;
      S.Get.FRoots[0].Name := 'the caller''s region';
      S.Get.CheckBlock(Module.InitializationSection, TPasProgram(Module).ProgramSection);
    end;
  end;
  S.Get.Flush(Report);
end;

end.
