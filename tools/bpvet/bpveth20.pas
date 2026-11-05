{ SPDX-License-Identifier: MIT }
{ bpvet: H20 (unxed/bp#207) and H21 (unxed/bp#218) of S17, in the typed mode on a module that resolved
  (bpvettyped.pas). FPC passes a String, a dynamic array, an interface, an open array or a record that holds one
  (TOwned, TShared) to a const or constref parameter without a reference, from any place: a local, a parameter, a
  global, a field, a var parameter, an element. The count of the argument stays where it was, so a write of that place
  while the call runs frees what the parameter names, and the callee reads freed memory (measured on FPC 3.2.2,
  safe/SPEC.md §26.2). The rule is the rule *change* of §24.9: a call is a change of every place the callee may write.
    S17  a call that passes a place P as such a const argument, when the call may write P or a place that overlaps it:
         - another var or out argument of the same call names P, a part of it, or a place P is a part of
           (Alias(X, X), UseBox(Box, Box));
         - the callee is a routine of the module that writes P, itself or through the routines of the module it calls,
           transitively: a local or a parameter of a routine around it (a nested routine, H20), a global, a field (any
           field of that name: the object it belongs to is not followed), an element of an array;
         - the callee is a procedure value, which may be any routine of the module used as a value;
         - the callee, or a routine of another unit that a callee of the module calls, is declared in the unit of the
           global P: a routine of another unit is taken to write the globals of its own unit only (the policy for
           what bpvet does not read), and the var and out arguments it is given.
         A place is a name (a local, a parameter, a global, a field of Self), a field path (A.B, Box.Get.FS: a class
         reference or a call result in the path is not a part of the place, only what follows it) or an element (A[I]
         is a part of A). A write is an assignment, a for loop variable, @X, a var or out argument (SetLength, Insert,
         Delete, SetString, Str, Read, ReadLn by name), and Reset or Move of a TOwned, Reset of a TShared or a TWeak,
         Put, Delete or Clear of a TMap, Reset or Release of a TRegion, FreeAll of a TArena on the place.
  Not followed: a write through a pointer or through an alias that a var parameter of the caller may be (the caller
  of the caller checks its own call), a write by the getter or the setter method of a property, an override that a
  virtual call may run instead of the method it names. A finding with // UNSAFE: <why> on its line (or in a comment
  block right above) is not reported; a // UNSAFE-UNIT: module is not checked. }
unit BpvetH20;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, PasTree, PasResolveEval, PasResolver, BpvetCore, BpvetNested, Safe;

procedure VetCheckH20(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);

implementation

type
  TListBox = specialize TOwned<TFPList>;
  TLinesBox = specialize TOwned<TStringList>;
  // UNSAFE: the key is the identity of an element of the tree, which is never dereferenced through it
  TIndex = specialize TMap<System.Pointer, Integer>;
  TDecls = array of TPasElement;

  { What a routine of the module may write, itself and through the routines of the module it calls. }
  TRoutine = record
    Proc: TPasProcedure;   // borrow: the checked module, alive during the check
    Whole: TDecls;         // the declarations written whole
    Part: TDecls;          // the declarations written in a part (a field, an element)
    Units: array of TPasModule;  // the units whose globals a routine of another unit it calls may write
    Calls: array of Integer;     // the routines of the module it calls
    CallsValues: Boolean;        // it calls a procedure value
  end;

  TH21 = class
  private
    FSrc: TVetSource;
    FResolver: TPasResolver;  // borrow: the resolver of the checked module, alive during the check
    FModule: TPasModule;      // borrow: the checked module, alive during the check
    FReport: TVetReport;
    FSeen: TLinesBox;
    FNodes: TListBox;
    FIndex: TIndex;           // a routine of the module (its declaration and its body) -> FRoutines
    FRoutines: array of TRoutine;
    FValues: array of Integer;    // the routines of the module used as procedure values
    FManaged: TIndex;         // a formal parameter -> 1 not managed, 2 managed
    FCur: Integer;            // the routine whose body is being read, -1 for a main block
    procedure Collect(El: TPasElement; Arg: Pointer);
    function Ref(const E: TPasElement): TPasElement;
    function TypeOf(const E: TPasElement): TPasType;
    function Managed(const T: TPasType; const Depth: Integer): Boolean;
    function IsManagedFormal(const A: TPasArgument): Boolean;
    function Marked(const El: TPasElement): Boolean;
    procedure Add(const El: TPasElement; const Msg: String);
    function RoutineOf(const D: TPasElement): Integer;
    procedure AddRoutines(const Decls: TPasDeclarations);
    function FieldOf(const D: TPasElement; const ForWrite: Boolean): TPasElement;
    function Place(const E: TPasExpr; const Exact: Boolean; out Decls: TDecls; out Elem: Boolean): Boolean;
    procedure AddWrite(const E: TPasExpr);
    function Callee(const P: TPasElement; out Recv: TPasExpr): TPasElement;
    function IsChange(const C: TPasElement): Boolean;
    procedure ReadBody(const I: Integer);
    procedure Propagate;
    function Overlaps(const Whole, Part: TDecls; const P: TDecls): Boolean;
    procedure CheckCall(const P: TParamsExpr);
    procedure CheckBody(const Body: TPasImplBlock);
  public
    constructor Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
    procedure Run;
    procedure Flush(var Report: TVetReport);
  end;

  TH21Box = specialize TOwned<TH21>;

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
  else if El is TUnaryExpr then
    Result := NameOf(TUnaryExpr(El).Operand)
  else
    Result := El.Name;
end;

{ The text of the place E, for a message: A.B[...] }
function TextOf(const E: TPasElement): String;
begin
  if (E is TBinaryExpr) and (TBinaryExpr(E).OpCode = eopSubIdent) then
    Result := TextOf(TBinaryExpr(E).left) + '.' + TextOf(TBinaryExpr(E).right)
  else if (E is TParamsExpr) and (TParamsExpr(E).Kind = pekArrayParams) then
    Result := TextOf(TParamsExpr(E).Value) + '[...]'
  else if (E is TParamsExpr) and (TParamsExpr(E).Kind = pekFuncParams) then
    Result := TextOf(TParamsExpr(E).Value) + '(...)'
  else
    Result := NameOf(E);
end;

function Has(const L: TDecls; const D: TPasElement): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(L) do
    if L[I] = D then
      Exit(True);
  Result := False;
end;

function Include(var L: TDecls; const D: TPasElement): Boolean;
begin
  Result := not Has(L, D);
  if Result then
  begin
    SetLength(L, Length(L) + 1);
    L[High(L)] := D;
  end;
end;

{ D is a global variable (or threadvar) of a unit or a program. }
function IsGlobal(const D: TPasElement): Boolean;
begin
  Result := (D is TPasVariable) and not (D is TPasConst) and not (D is TPasProperty) and (D.Parent is TPasSection);
end;

constructor TH21.Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
begin
  inherited Create;
  FSrc := ASrc;
  // borrow: the resolver outlives the check (VetResolve)
  FResolver := AResolver;
  // borrow: the module outlives the check (VetResolve)
  FModule := AModule;
  FSeen := TLinesBox.Own(TStringList.Create);
  FSeen.Get.Sorted := True;
  FNodes := TListBox.Own(TFPList.Create);
  FCur := -1;
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure TH21.Collect(El: TPasElement; Arg: Pointer);
begin
  FNodes.Get.Add(El);
end;

function TH21.Ref(const E: TPasElement): TPasElement;
begin
  Result := nil;
  if (E <> nil) and (E.CustomData is TResolvedReference) then
    Result := TResolvedReference(E.CustomData).Declaration;
end;

function TH21.TypeOf(const E: TPasElement): TPasType;
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

{ A value of type T holds a reference that a const parameter does not count: a String, a dynamic or open array, an
  interface, or a record or a static array with one inside. }
function TH21.Managed(const T: TPasType; const Depth: Integer): Boolean;
var
  I: Integer;
  M: TPasElement;
  R: TPasResolverResult;
begin
  Result := False;
  if (T = nil) or (Depth > 8) then
    Exit;
  if T is TPasArrayType then
  begin
    if Length(TPasArrayType(T).Ranges) = 0 then
      Exit(True);
    try
      FResolver.ComputeElement(TPasArrayType(T).ElType, R, []);
    except
      on Exception do
        Exit(False);
    end;
    Exit((R.BaseType in [btString, btAnsiString, btUnicodeString, btWideString, btRawByteString])
      or Managed(R.LoTypeEl, Depth + 1));
  end;
  if T is TPasClassType then
    Exit(TPasClassType(T).ObjKind = okInterface);
  if T is TPasRecordType then
    for I := 0 to TPasRecordType(T).Members.Count - 1 do
    begin
      M := TPasElement(TPasRecordType(T).Members[I]);
      if M.ClassType <> TPasVariable then
        Continue;
      try
        FResolver.ComputeElement(TPasVariable(M).VarType, R, []);
      except
        on Exception do
          Continue;
      end;
      if (R.BaseType in [btString, btAnsiString, btUnicodeString, btWideString, btRawByteString])
        or Managed(R.LoTypeEl, Depth + 1) then
        Exit(True);
    end;
end;

function TH21.IsManagedFormal(const A: TPasArgument): Boolean;
var
  C: Integer;
  R: TPasResolverResult;
begin
  if A.ArgType = nil then
    Exit(False); // an untyped const: S25
  C := FManaged.Get(A, 0);
  if C <> 0 then
    Exit(C = 2);
  Result := False;
  try
    FResolver.ComputeElement(A, R, []);
    Result := (R.BaseType in [btString, btAnsiString, btUnicodeString, btWideString, btRawByteString])
      or Managed(R.LoTypeEl, 0);
  except
    on Exception do
      Result := False;
  end;
  if Result then
    FManaged.Put(A, 2)
  else
    FManaged.Put(A, 1);
end;

{ // UNSAFE: at the end of the line of El or on a comment line right above it (more comment lines may follow). }
function TH21.Marked(const El: TPasElement): Boolean;
var
  Row: Integer;
  Line: String;
begin
  Row := El.SourceLinenumber;
  if Pos('// UNSAFE:', VetLine(FSrc, Row)) > 0 then
    Exit(True);
  Dec(Row);
  while Row >= 1 do
  begin
    Line := TrimLeft(VetLine(FSrc, Row));
    if Copy(Line, 1, 2) <> '//' then
      Break;
    if Pos('// UNSAFE:', Line) = 1 then
      Exit(True);
    Dec(Row);
  end;
  Result := False;
end;

procedure TH21.Add(const El: TPasElement; const Msg: String);
var
  Row: Integer;
  Seen: String;
begin
  if (El.SourceFilename <> '') and not SameFileName(ExpandFileName(El.SourceFilename), ExpandFileName(FSrc.FileName))
    then
    Exit; // an include file: not checked here
  Row := El.SourceLinenumber;
  if Marked(El) then
    Exit;
  Seen := Format('%.6d %s', [Row, Msg]);
  if FSeen.Get.IndexOf(Seen) >= 0 then
    Exit;
  FSeen.Get.Add(Seen);
  VetAdd(FReport, FSrc.FileName, Row, VetWordColumn(VetLine(FSrc, Row), NameOf(El)), vsError, 'S17', Msg);
end;

{ The index of the routine of the module that D (a declaration or a body) is, or -1. }
function TH21.RoutineOf(const D: TPasElement): Integer;
begin
  if D = nil then
    Exit(-1);
  Result := FIndex.Get(D, -1);
end;

{ The routines with a body in Decls, and those nested in them. }
procedure TH21.AddRoutines(const Decls: TPasDeclarations);
var
  I, K: Integer;
  D: TPasElement;
  P: TPasProcedure;
begin
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    D := TPasElement(Decls.Declarations[I]);
    if not ((D is TPasProcedure) and (TPasProcedure(D).Body <> nil) and (TPasProcedure(D).Body.Body <> nil)) then
      Continue;
    P := TPasProcedure(D);
    K := Length(FRoutines);
    SetLength(FRoutines, K + 1);
    FRoutines[K] := Default(TRoutine);
    // borrow: the routine belongs to the checked module
    FRoutines[K].Proc := P;
    FIndex.Put(P, K);
    if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
      FIndex.Put(TPasProcedureScope(P.CustomData).DeclarationProc, K);
    AddRoutines(P.Body);
  end;
end;

{ The field that the property D reads or writes, or D itself when it is not a property; nil for a property with a
  getter or a setter method. }
function TH21.FieldOf(const D: TPasElement; const ForWrite: Boolean): TPasElement;
var
  A: TPasExpr;
begin
  if not (D is TPasProperty) then
    Exit(D);
  if ForWrite then
    A := TPasProperty(D).WriteAccessor
  else
    A := TPasProperty(D).ReadAccessor;
  Result := Ref(A);
  if not (Result is TPasVariable) or (Result is TPasProperty) or (Result is TPasConst) then
    Result := nil;
end;

{ The place E names, as the declarations along it (the last one is what E is); Elem: E is an element of the last.
  A class reference, a pointer or a call in the path ends the place before it: only what follows is the place. Exact:
  read the types to tell a record from a class reference (for a const argument); without it every name of the path
  is a part of the place (for a write, which is then taken as a write of a part of each). False when E is not a place:
  a call, a literal, a constant, a property with a getter. }
function TH21.Place(const E: TPasExpr; const Exact: Boolean; out Decls: TDecls; out Elem: Boolean): Boolean;
var
  D: TPasElement;
  T: TPasType;
  Sub: TDecls;
  SubElem: Boolean;
  B: TBinaryExpr;
begin
  Decls := nil;
  Elem := False;
  Result := False;
  if E is TPrimitiveExpr then
  begin
    if TPrimitiveExpr(E).Kind <> pekIdent then
      Exit;
    D := FieldOf(Ref(E), not Exact);
    if not (((D is TPasVariable) and not (D is TPasConst)) or (D is TPasArgument) or (D is TPasResultElement)) then
      Exit;
    SetLength(Decls, 1);
    Decls[0] := D;
    Exit(True);
  end;
  if (E is TBinaryExpr) and (TBinaryExpr(E).OpCode = eopSubIdent) then
  begin
    B := TBinaryExpr(E);
    if not (B.right is TPrimitiveExpr) then
      Exit;
    D := FieldOf(Ref(B.right), not Exact);
    if not ((D is TPasVariable) and not (D is TPasConst)) then
      Exit;
    // what is before the field: a record is a part of the place, a reference or a call is not
    Sub := nil;
    if not ((B.left is TSelfExpr) or (Ref(B.left) is TPasType) or (Ref(B.left) is TPasModule)) then
    begin
      if Exact then
      begin
        T := TypeOf(B.left);
        if (T is TPasRecordType) or ((T is TPasArrayType) and (Length(TPasArrayType(T).Ranges) > 0)) then
        begin
          if not Place(B.left, Exact, Sub, SubElem) then
            Exit; // a field of a temporary record
        end;
      end
      else if not Place(B.left, Exact, Sub, SubElem) then
        Sub := nil;
    end;
    Decls := Sub;
    SetLength(Decls, Length(Decls) + 1);
    Decls[High(Decls)] := D;
    Exit(True);
  end;
  if (E is TParamsExpr) and (TParamsExpr(E).Kind = pekArrayParams) then
  begin
    if Exact then
    begin
      T := TypeOf(TParamsExpr(E).Value);
      if not ((T is TPasArrayType) or (T is TPasRecordType)) then
        Exit; // a string index is a Char; a default property of an object is a call
    end;
    Result := Place(TParamsExpr(E).Value, Exact, Decls, SubElem);
    Elem := Result;
    Exit;
  end;
  if (E is TParamsExpr) and (TParamsExpr(E).Kind = pekFuncParams) and (Length(TParamsExpr(E).Params) = 1)
    and (Ref(TParamsExpr(E).Value) is TPasType) then
    Exit(Place(TParamsExpr(E).Params[0], Exact, Decls, Elem)); // a type cast names its argument
end;

{ E is written: its place goes into the writes of the routine being read. }
procedure TH21.AddWrite(const E: TPasExpr);
var
  Decls: TDecls;
  Elem: Boolean;
  I: Integer;
begin
  if (FCur < 0) or not Place(E, False, Decls, Elem) then
    Exit;
  for I := 0 to High(Decls) - 1 do
    Include(FRoutines[FCur].Part, Decls[I]);
  if Elem then
    Include(FRoutines[FCur].Part, Decls[High(Decls)])
  else
    Include(FRoutines[FCur].Whole, Decls[High(Decls)]);
end;

{ The routine or the procedure variable that the call P (a TParamsExpr, or a name called without parentheses) calls;
  Recv: the receiver of a method, else nil. }
function TH21.Callee(const P: TPasElement; out Recv: TPasExpr): TPasElement;
var
  V: TPasElement;
begin
  Recv := nil;
  V := P;
  if V is TParamsExpr then
    V := TParamsExpr(V).Value;
  if (V is TBinaryExpr) and (TBinaryExpr(V).OpCode = eopSubIdent) then
  begin
    Result := Ref(TBinaryExpr(V).right);
    Recv := TBinaryExpr(V).left;
  end
  else
    Result := Ref(V);
end;

{ C is a method that changes the record it is called on (the change operations of the roots, §24.9). }
function TH21.IsChange(const C: TPasElement): Boolean;
var
  N, T: String;
begin
  Result := False;
  if not ((C is TPasProcedure) and (C.Parent is TPasRecordType)) then
    Exit;
  N := LowerCase(C.Name);
  T := LowerCase(C.Parent.Name);
  if (Copy(T, 1, 6) = 'towned') then
    Result := (N = 'reset') or (N = 'move')
  else if (Copy(T, 1, 7) = 'tshared') or (Copy(T, 1, 5) = 'tweak') then
    Result := N = 'reset'
  else if Copy(T, 1, 4) = 'tmap' then
    Result := (N = 'put') or (N = 'delete') or (N = 'clear') or (N = 'ref')
  else if T = 'tregion' then
    Result := (N = 'reset') or (N = 'release')
  else if Copy(T, 1, 6) = 'tarena' then
    Result := N = 'freeall';
end;

{ The writes and the calls of the routine FRoutines[I], from its body. }
procedure TH21.ReadBody(const I: Integer);
var
  J, K, Q: Integer;
  N, C: TPasElement;
  P: TParamsExpr;
  Recv: TPasExpr;
  Name: String;
  Hit: Boolean;
  Formal: TPasArgument;
  T: TPasType;
begin
  FCur := I;
  FNodes.Get.Clear;
  FRoutines[I].Proc.Body.Body.ForEachCall(@Collect, nil);
  for J := 0 to FNodes.Get.Count - 1 do
  begin
    N := TPasElement(FNodes.Get[J]);
    if N is TPasImplAssign then
      AddWrite(TPasImplAssign(N).left)
    else if N is TPasImplForLoop then
      AddWrite(TPasImplForLoop(N).VariableName)
    else if (N is TUnaryExpr) and (TUnaryExpr(N).OpCode = eopAddress) then
      AddWrite(TUnaryExpr(N).Operand)
    else if (N is TParamsExpr) and (TParamsExpr(N).Kind = pekFuncParams) then
    begin
      P := TParamsExpr(N);
      C := Callee(P, Recv);
      if C = nil then
        Continue;
      Name := LowerCase(C.Name);
      for K := 0 to High(P.Params) do
      begin
        Hit := ((K = 0) and ((Name = 'setlength') or (Name = 'uniquestring') or (Name = 'delete')
          or (Name = 'setstring') or (Name = 'fillchar'))) or ((K = 1) and (Name = 'insert'))
          or ((K = High(P.Params)) and (K > 0) and (Name = 'str')) or (Name = 'read') or (Name = 'readln');
        if not Hit and (C is TPasProcedure) and (TPasProcedure(C).ProcType <> nil)
          and (K < TPasProcedure(C).ProcType.Args.Count) then
        begin
          Formal := TPasArgument(TPasProcedure(C).ProcType.Args[K]);
          Hit := Formal.Access in [argVar, argOut];
        end;
        if Hit then
          AddWrite(P.Params[K]);
      end;
    end
    else if (N is TBinaryExpr) and (TBinaryExpr(N).OpCode = eopSubIdent) then
    begin
      // Box.Reset, M.Put(K, V): a change of the record it is called on
      if IsChange(Ref(TBinaryExpr(N).right)) then
        AddWrite(TBinaryExpr(N).left);
    end
    else if N is TPrimitiveExpr then
    begin
      C := Ref(N);
      if C is TPasProcedure then
      begin
        K := RoutineOf(C);
        if VetUseOf(N) = 'v' then
        begin
          if (K >= 0) and (K <> I) then
          begin
            Hit := False;
            for Q := 0 to High(FValues) do
              Hit := Hit or (FValues[Q] = K);
            if not Hit then
            begin
              SetLength(FValues, Length(FValues) + 1);
              FValues[High(FValues)] := K;
            end;
          end;
        end
        else if K >= 0 then
        begin
          SetLength(FRoutines[I].Calls, Length(FRoutines[I].Calls) + 1);
          FRoutines[I].Calls[High(FRoutines[I].Calls)] := K;
        end
        else if (C.GetModule <> nil) and (C.GetModule <> FModule) and not (C.CustomData is TResElDataBuiltInProc) then
        begin
          Hit := False;
          for Q := 0 to High(FRoutines[I].Units) do
            Hit := Hit or (FRoutines[I].Units[Q] = C.GetModule);
          if not Hit then
          begin
            SetLength(FRoutines[I].Units, Length(FRoutines[I].Units) + 1);
            // borrow: the unit outlives the check (the session of VetResolve)
            FRoutines[I].Units[High(FRoutines[I].Units)] := C.GetModule;
          end;
        end;
      end
      else if ((C is TPasVariable) or (C is TPasArgument)) and (N.Parent is TParamsExpr)
        and (TParamsExpr(N.Parent).Value = N) and (TParamsExpr(N.Parent).Kind = pekFuncParams) then
      begin
        T := TypeOf(C);
        if T is TPasProcedureType then
          FRoutines[I].CallsValues := True;
      end;
    end;
  end;
  FCur := -1;
end;

{ The writes of the callees go into their callers until nothing grows. }
procedure TH21.Propagate;
var
  I, J, K, Q: Integer;
  Changed, Hit: Boolean;
  Callees: array of Integer;
begin
  repeat
    Changed := False;
    for I := 0 to High(FRoutines) do
    begin
      Callees := Copy(FRoutines[I].Calls);
      if FRoutines[I].CallsValues then
        for J := 0 to High(FValues) do
        begin
          SetLength(Callees, Length(Callees) + 1);
          Callees[High(Callees)] := FValues[J];
        end;
      for J := 0 to High(Callees) do
      begin
        K := Callees[J];
        if K = I then
          Continue;
        for Q := 0 to High(FRoutines[K].Whole) do
          if Include(FRoutines[I].Whole, FRoutines[K].Whole[Q]) then
            Changed := True;
        for Q := 0 to High(FRoutines[K].Part) do
          if Include(FRoutines[I].Part, FRoutines[K].Part[Q]) then
            Changed := True;
        for Q := 0 to High(FRoutines[K].Units) do
        begin
          Hit := False;
          for J2 := 0 to High(FRoutines[I].Units) do
            Hit := Hit or (FRoutines[I].Units[J2] = FRoutines[K].Units[Q]);
          if not Hit then
          begin
            SetLength(FRoutines[I].Units, Length(FRoutines[I].Units) + 1);
            // borrow: the unit outlives the check (the session of VetResolve)
            FRoutines[I].Units[High(FRoutines[I].Units)] := FRoutines[K].Units[Q];
            Changed := True;
          end;
        end;
      end;
    end;
  until not Changed;
end;

{ A write (Whole, Part) overlaps the place P: it writes what P is, or the whole of a place P is a part of. }
function TH21.Overlaps(const Whole, Part: TDecls; const P: TDecls): Boolean;
var
  I: Integer;
begin
  Result := (Length(P) > 0) and (Has(Whole, P[High(P)]) or Has(Part, P[High(P)]));
  for I := 0 to High(P) - 1 do
    Result := Result or Has(Whole, P[I]);
end;

procedure TH21.CheckCall(const P: TParamsExpr);
var
  C: TPasElement;
  Recv: TPasExpr;
  PT: TPasProcedureType;
  T: TPasType;
  I, J, K: Integer;
  A: TPasArgument;
  Decls, Other: TDecls;
  Elem, OtherElem: Boolean;
  Whole, Part: TDecls;
  Via, Why, Head: String;
  W: TRoutine;
begin
  C := Callee(P, Recv);
  PT := nil;
  K := -1;
  if C is TPasProcedure then
  begin
    PT := TPasProcedure(C).ProcType;
    K := RoutineOf(C);
    Via := C.Name;
  end
  else if (C is TPasVariable) or (C is TPasArgument) then
  begin
    T := TypeOf(C);
    if not (T is TPasProcedureType) then
      Exit;
    PT := TPasProcedureType(T);
    Via := 'the procedure value ' + C.Name;
  end;
  if PT = nil then
    Exit;
  for J := 0 to High(P.Params) do
  begin
    if J >= PT.Args.Count then
      Break;
    A := TPasArgument(PT.Args[J]);
    if not (A.Access in [argConst, argConstRef]) or not IsManagedFormal(A) then
      Continue;
    if not Place(P.Params[J], True, Decls, Elem) then
      Continue;
    Why := '';
    Head := TextOf(P.Params[J]);
    // another var or out argument of the call names the same place
    for I := 0 to High(P.Params) do
    begin
      if (I = J) or (I >= PT.Args.Count) or not (TPasArgument(PT.Args[I]).Access in [argVar, argOut]) then
        Continue;
      if not Place(P.Params[I], False, Other, OtherElem) then
        Continue;
      Whole := nil;
      Part := nil;
      for K := 0 to High(Other) - 1 do
        Include(Part, Other[K]);
      if OtherElem then
        Include(Part, Other[High(Other)])
      else
        Include(Whole, Other[High(Other)]);
      if Overlaps(Whole, Part, Decls) or Overlaps(Nil, Nil, Decls) then
        ;
      if Overlaps(Whole, Part, Decls) or Has(Decls, Other[High(Other)]) then
      begin
        Why := Format('the var/out argument %s of the same call names it too, so %s may write it while %s names it',
          [TextOf(P.Params[I]), Via, A.Name]);
        Break;
      end;
    end;
    K := RoutineOf(C);
    if (Why = '') and (K >= 0) then
    begin
      W := FRoutines[K];
      if Overlaps(W.Whole, W.Part, Decls) then
        Why := Format('%s (or a routine of this module it calls) writes it', [Via])
      else if IsGlobal(Decls[0]) then
        for I := 0 to High(W.Units) do
          if W.Units[I] = Decls[0].GetModule then
            Why := Format('%s calls a routine of the unit %s, which may write its global %s', [Via,
              W.Units[I].Name, Decls[0].Name]);
    end
    else if (Why = '') and (C is TPasProcedure) then
    begin
      if IsGlobal(Decls[0]) and (C.GetModule = Decls[0].GetModule) and (C.GetModule <> FModule) then
        Why := Format('%s is a routine of the unit %s, which may write its global %s', [Via, C.GetModule.Name,
          Decls[0].Name]);
    end
    else if Why = '' then
    begin
      // a procedure value: any routine of the module used as one
      for I := 0 to High(FValues) do
        if (Why = '') and Overlaps(FRoutines[FValues[I]].Whole, FRoutines[FValues[I]].Part, Decls) then
          Why := Format('%s may be %s, which (or a routine of this module it calls) writes it', [Via,
            FRoutines[FValues[I]].Proc.Name]);
    end;
    if Why = '' then
      Continue;
    Add(P.Params[J], Format('H21 (unxed/bp#218): %s is passed to the const parameter %s of %s, and %s: FPC passes a '
      + 'String, a dynamic array, an interface or a record that holds one to a const parameter without a reference, '
      + 'from any place, so the write frees what %s names and it reads freed memory; make %s a value parameter, or '
      + 'pass a copy (a local copied first)', [Head, A.Name, Via, Why, A.Name, A.Name]));
  end;
end;

procedure TH21.CheckBody(const Body: TPasImplBlock);
var
  Calls: TListBox;
  I: Integer;
begin
  if Body = nil then
    Exit;
  FNodes.Get.Clear;
  Body.ForEachCall(@Collect, nil);
  Calls := TListBox.Own(TFPList.Create);
  for I := 0 to FNodes.Get.Count - 1 do
    if (TObject(FNodes.Get[I]) is TParamsExpr) and (TParamsExpr(FNodes.Get[I]).Kind = pekFuncParams)
      and (Length(TParamsExpr(FNodes.Get[I]).Params) > 0) then
      Calls.Get.Add(FNodes.Get[I]);
  for I := 0 to Calls.Get.Count - 1 do
    CheckCall(TParamsExpr(Calls.Get[I]));
end;

procedure TH21.Run;
var
  I: Integer;
begin
  AddRoutines(FModule.InterfaceSection);
  AddRoutines(FModule.ImplementationSection);
  if FModule is TPasProgram then
    AddRoutines(TPasProgram(FModule).ProgramSection);
  for I := 0 to High(FRoutines) do
    ReadBody(I);
  Propagate;
  for I := 0 to High(FRoutines) do
    CheckBody(FRoutines[I].Proc.Body.Body);
  CheckBody(FModule.InitializationSection);
  CheckBody(FModule.FinalizationSection);
end;

procedure TH21.Flush(var Report: TVetReport);
var
  I: Integer;
begin
  for I := 0 to High(FReport.Findings) do
    with FReport.Findings[I] do
      VetAdd(Report, FileName, Row, Col, Severity, Rule, Msg);
end;

procedure VetCheckH20(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);
var
  H: TH21Box;
  I: Integer;
begin
  for I := 0 to High(Src.Lines) do
    if Pos('// UNSAFE-UNIT:', Src.Lines[I]) = 1 then
      Exit;
  H := TH21Box.Own(TH21.Create(Src, Resolver, Module));
  H.Get.Run;
  H.Get.Flush(Report);
end;

end.
