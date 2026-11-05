{ SPDX-License-Identifier: MIT }
{ bpvet: the calls of Hold of a scope (TScopeRef, the variable of for S in Scope) and of a TRegion (safe/SPEC.md
  §21.1). Hold(out V; Obj: TObject) takes an untyped out, so the compiler accepts any variable; this check runs in the
  typed mode on a module that resolved (bpvettyped.pas):
    S6   the shape: V is a plain local variable of the routine (not a field, a global, a parameter or an expression) of
         a class type, and Obj is a constructor call TFoo.Create(...) of that class or of a descendant. A Hold of that
         shape owns the new object, so the untyped S6 finding of its line is dropped;
    S17  V does not escape: it is not the right side of an assignment to anything but a local of the routine (the
         result, a field, an element, a global or a parameter), not the value of Exit, not an argument of Send of a
         TChan and not an argument of a constructor of a TTask descendant (passing it to another routine is a borrow);
         and it is not read after its scope: after the end of the loop for S in Scope that holds it, or after a later
         Reset or Release of the TRegion R of R.Hold (or R := TRegion.Create), until it is assigned again. The order
         is that of the lines of the source: a read on an earlier line that runs later (in the next round of an outer
         loop) is not seen. A Hold through a TScopeRef local that is not the variable of an enclosing loop for S in
         Scope is a finding too.
  The same pass checks the owners of the tree of TComponent (safe/SPEC.md §21.4). A component class is a class that
  descends from Classes.TComponent, or from a class named TComponent declared in the checked module (a stub, so that a
  test needs no LCL). An owned call is TFoo.Create(AOwner, ...) of a component class whose constructor takes a
  component class first and whose first argument is a class instance (not nil):
    S6   an owned call gives the new object to its owner, so the untyped S6 finding of its line is dropped when every
         constructor call of the line is an owned call or goes at once into Own, Share, Adopt, Go, Hold or raise;
         TFoo.Create(nil) stays a finding;
    S5   a published field of a component class whose type is a component class (Button1: TButton, written by the
         form designer; the default section of a class compiled with M+ is published) is filled by the streaming system
         with the form as the owner, so the untyped S5 finding of its line is dropped; other fields keep S5;
    S17  the result of an owned call is a borrow rooted in the owner: an owned call or a variable that holds one (a
         local or a field assigned from an owned call in the routine, from that line until it is assigned something
         else, and a published component field of a component class) is not destroyed by .Free or FreeAndNil (.Destroy
         is S3) and not given to Own, Share or Adopt, and an owned call is not the object of a Hold: the object would
         have two owners. Storing it in a field is allowed.
  The same pass checks Ref of a TMap (safe/SPEC.md §25.3):
    S27  M.Ref(K, D) is the place of a value in the slots of the map, which the next change of the map may move: the
         call is dereferenced at once (M.Ref(K, D)^), never assigned, passed or kept.
  A finding with // UNSAFE: <why> on its line (or in a comment block right above) is not reported; a // UNSAFE-UNIT:
  module is not checked. }
unit BpvetHold;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, PasTree, PasResolveEval, PasResolver, BpvetCore, Safe;

procedure VetCheckHold(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);

implementation

type
  TLinesBox = specialize TOwned<TStringList>;
  TListBox = specialize TOwned<TFPList>;

  THold = class
  private
    FSrc: TVetSource;
    FResolver: TPasResolver;  // borrow: the resolver of the checked module, alive during the check
    FReport: TVetReport;
    FLines: TLinesBox;        // name=file for the sources of include files
    FSeen: TLinesBox;
    FOwned: TLinesBox;        // 'file row': the rows of the constructor calls of valid Holds (no untyped S6 there)
    FNodes: TListBox;         // what Collect gathers
    FBody: TListBox;          // the elements of the body of the routine being checked
    FProc: TPasProcedure;     // borrow: the routine being checked
    FModule: TPasModule;      // borrow: the checked module, alive during the check
    FDrop: TLinesBox;         // 'S5 file row' and 'S6 file row': untyped findings that the component tree answers
    FFields: TListBox;        // the published component fields of the component classes of the module
    procedure Collect(El: TPasElement; Arg: Pointer);
    function Ref(const E: TPasElement): TPasElement;
    function TypeOf(const E: TPasElement): TPasType;
    function LineOf(const FileName: String; const Row: Integer): String;
    function Marked(const El: TPasElement): Boolean;
    procedure Add(const El: TPasElement; const Rule, Msg: String);
    function IsHold(const E: TParamsExpr; out Recv: TPasExpr): Boolean;
    function Strip(const E: TPasExpr): TPasExpr;
    function Descends(const C: TPasType; const Name: String): Boolean;
    function IsA(const C, Base: TPasType): Boolean;
    function ConstructorClass(const E: TPasExpr; out At: TPasExpr): TPasType;
    function IsLocal(const D: TPasElement): Boolean;
    function What(const L: TPasExpr): String;
    function Shape(const E: TParamsExpr): TPasElement;
    procedure Escapes(const V: TPasElement);
    function IsCallOn(const E: TPasElement; const Recv: TPasElement; const Names: String): Boolean;
    function ScopeLoop(const Call: TParamsExpr; const Recv: TPasElement): TPasImplForLoop;
    function LastRow(const El: TPasElement): Integer;
    function Assigns(const E: TPasElement; const V: TPasElement): Boolean;
    procedure ReadsAfter(const V: TPasElement; const Kill: Integer; const Why: String);
    procedure After(const Call: TParamsExpr; const Recv: TPasExpr; const V: TPasElement);
    function IsComponent(const C: TPasType): Boolean;
    function OwnedCall(const E: TPasExpr): Boolean;
    function Callee(const P: TParamsExpr): TPasElement;
    function IsOwnerCall(const P: TParamsExpr): Boolean;
    function OwnedByShape(const E: TPasElement): Boolean;
    function Named(const E: TPasExpr): TPasElement;
    function OwnedVar(const D: TPasElement; const Row: Integer): Boolean;
    function Key(const Rule: String; const El: TPasElement): String;
    procedure Destroyed(const At: TPasElement; const D: TPasElement; const How: String);
    procedure Twice(const At: TPasExpr; const Owner: String);
  public
    constructor Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
    function IsMapRef(const P: TParamsExpr): Boolean;
    procedure CheckProc(const P: TPasProcedure);
    procedure CheckDecls(const Decls: TPasDeclarations);
    procedure CollectFields(const L: TFPList);
    procedure CheckComponents(const Body: TPasElement);
    procedure CheckComponentDecls(const Decls: TPasDeclarations);
    procedure Flush(var Report: TVetReport);
  end;

  THoldBox = specialize TOwned<THold>;

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

constructor THold.Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
begin
  inherited Create;
  FSrc := ASrc;
  // borrow: the resolver outlives the check (VetResolve)
  FResolver := AResolver;
  // borrow: the module outlives the check (VetResolve)
  FModule := AModule;
  FDrop := TLinesBox.Own(TStringList.Create);
  FDrop.Get.Sorted := True;
  FDrop.Get.Duplicates := dupIgnore;
  FFields := TListBox.Own(TFPList.Create);
  FLines := TLinesBox.Own(TStringList.Create);
  FLines.Get.OwnsObjects := True;
  FSeen := TLinesBox.Own(TStringList.Create);
  FSeen.Get.Sorted := True;
  FOwned := TLinesBox.Own(TStringList.Create);
  FOwned.Get.Sorted := True;
  FOwned.Get.Duplicates := dupIgnore;
  FNodes := TListBox.Own(TFPList.Create);
  FBody := TListBox.Own(TFPList.Create);
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure THold.Collect(El: TPasElement; Arg: Pointer);
begin
  FNodes.Get.Add(El);
end;

function THold.Ref(const E: TPasElement): TPasElement;
begin
  Result := nil;
  if (E <> nil) and (E.CustomData is TResolvedReference) then
    Result := TResolvedReference(E.CustomData).Declaration;
end;

function THold.TypeOf(const E: TPasElement): TPasType;
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

function THold.LineOf(const FileName: String; const Row: Integer): String;
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

{ // UNSAFE: at the end of the line of El or on a comment line right above it (more comment lines may follow). }
function THold.Marked(const El: TPasElement): Boolean;
var
  Row: Integer;
  Line: String;
begin
  Row := El.SourceLinenumber;
  if Pos('// UNSAFE:', LineOf(El.SourceFilename, Row)) > 0 then
    Exit(True);
  Dec(Row);
  while Row >= 1 do
  begin
    Line := TrimLeft(LineOf(El.SourceFilename, Row));
    if Copy(Line, 1, 2) <> '//' then
      Break;
    if Pos('// UNSAFE:', Line) = 1 then
      Exit(True);
    Dec(Row);
  end;
  Result := False;
end;

procedure THold.Add(const El: TPasElement; const Rule, Msg: String);
var
  Row: Integer;
  Seen, FileName: String;
begin
  Row := El.SourceLinenumber;
  if Marked(El) then
    Exit;
  Seen := Format('%s %.6d %s %s', [El.SourceFilename, Row, Rule, Msg]);
  if FSeen.Get.IndexOf(Seen) >= 0 then
    Exit;
  FSeen.Get.Add(Seen);
  // an element of an include file is reported in that file
  FileName := FSrc.FileName;
  if (El.SourceFilename <> '') and not SameFileName(ExpandFileName(El.SourceFilename), ExpandFileName(FileName)) then
    FileName := El.SourceFilename;
  VetAdd(FReport, FileName, Row, VetWordColumn(LineOf(El.SourceFilename, Row), NameOf(El)), vsError, Rule, Msg);
end;

{ E is a call of Hold of a TScopeRef or a TRegion; Recv: the receiver (nil inside with). }
function THold.IsHold(const E: TParamsExpr; out Recv: TPasExpr): Boolean;
var
  D: TPasElement;
begin
  Recv := nil;
  Result := False;
  if E.Kind <> pekFuncParams then
    Exit;
  if (E.Value is TBinaryExpr) and (TBinaryExpr(E.Value).OpCode = eopSubIdent) then
  begin
    D := Ref(TBinaryExpr(E.Value).right);
    Recv := TBinaryExpr(E.Value).left;
  end
  else
    D := Ref(E.Value);
  Result := (D is TPasProcedure) and SameText(D.Name, 'Hold') and (D.Parent is TPasRecordType)
    and (SameText(D.Parent.Name, 'TScopeRef') or SameText(D.Parent.Name, 'TRegion'));
end;

{ E without type casts: TFoo(X) and X as TFoo are X. }
function THold.Strip(const E: TPasExpr): TPasExpr;
begin
  Result := E;
  while True do
    if (Result is TParamsExpr) and (TParamsExpr(Result).Kind = pekFuncParams)
      and (Length(TParamsExpr(Result).Params) = 1) and (Ref(TParamsExpr(Result).Value) is TPasType) then
      Result := TParamsExpr(Result).Params[0]
    else if (Result is TBinaryExpr) and (TBinaryExpr(Result).OpCode = eopAs) then
      Result := TBinaryExpr(Result).left
    else
      Exit;
end;

{ The class C or one of its ancestors is named Name. }
function THold.Descends(const C: TPasType; const Name: String): Boolean;
var
  X: TPasType;
  Depth: Integer;
begin
  X := C;
  Depth := 0;
  while (X is TPasClassType) and (Depth < 64) do
  begin
    if SameText(X.Name, Name) then
      Exit(True);
    X := TypeOf(TPasClassType(X).AncestorType);
    Inc(Depth);
  end;
  Result := False;
end;

{ The class C is Base or a descendant of it (a class with no written ancestor descends from TObject). }
function THold.IsA(const C, Base: TPasType): Boolean;
var
  X: TPasType;
  Depth: Integer;
begin
  X := C;
  Depth := 0;
  while (X is TPasClassType) and (Depth < 64) do
  begin
    if (X = Base) or (SameText(X.Name, Base.Name) and (TPasClassType(X).IsForward
      or ((Base is TPasClassType) and TPasClassType(Base).IsForward))) then
      Exit(True);
    if TPasClassType(X).AncestorType = nil then
      Exit(SameText(Base.Name, 'TObject'));
    X := TypeOf(TPasClassType(X).AncestorType);
    Inc(Depth);
  end;
  Result := False;
end;

{ When E is a constructor call TFoo.Create or TFoo.Create(...): the class TFoo, and At is the call; else nil. }
function THold.ConstructorClass(const E: TPasExpr; out At: TPasExpr): TPasType;
var
  V: TPasExpr;
  T: TPasType;
begin
  Result := nil;
  At := E;
  V := E;
  if (V is TParamsExpr) and (TParamsExpr(V).Kind = pekFuncParams) then
    V := TParamsExpr(V).Value;
  if not ((V is TBinaryExpr) and (TBinaryExpr(V).OpCode = eopSubIdent)) then
    Exit;
  if not (Ref(TBinaryExpr(V).right) is TPasConstructor) or not (Ref(TBinaryExpr(V).left) is TPasType) then
    Exit;
  T := TypeOf(TBinaryExpr(V).left);
  if (T is TPasClassType) and (TPasClassType(T).ObjKind = okClass) then
    Result := T;
end;

{ D is a variable declared by the routine being checked. }
function THold.IsLocal(const D: TPasElement): Boolean;
begin
  Result := (D is TPasVariable) and not (D is TPasConst) and not (D is TPasProperty) and (FProc.Body <> nil)
    and (D.Parent = FProc.Body);
end;

{ How a message names the target L of an assignment that is not a local of the routine. }
function THold.What(const L: TPasExpr): String;
var
  D: TPasElement;
begin
  if not (L is TPrimitiveExpr) then
    Exit('a field or an element');
  D := Ref(L);
  if (D is TPasResultElement) or (D is TPasProcedure) then
    Result := 'the result'
  else if D is TPasArgument then
    Result := 'the parameter ' + D.Name
  else if (D is TPasVariable) and ((D.Parent is TPasClassType) or (D.Parent is TPasRecordType)) then
    Result := 'the field ' + D.Name
  else if (D is TPasVariable) and (D.Parent is TProcedureBody) then
    Result := 'the local ' + D.Name + ' of another routine'
  else if D <> nil then
    Result := 'the global ' + D.Name
  else
    Result := NameOf(L);
end;

{ S6: the shape of the Hold call E; the declaration of V when it is right, else nil. }
function THold.Shape(const E: TParamsExpr): TPasElement;
var
  D: TPasElement;
  VT, CT: TPasType;
  At: TPasExpr;
begin
  Result := nil;
  if Length(E.Params) <> 2 then
    Exit;
  D := nil;
  if (E.Params[0] is TPrimitiveExpr) and (TPrimitiveExpr(E.Params[0]).Kind = pekIdent) then
    D := Ref(E.Params[0]);
  if not IsLocal(D) then
  begin
    Add(E.Params[0], 'S6', Format('Hold(%s, ...): the first argument must be a plain local variable of this routine '
      + '(not a field, a global, a parameter or an expression): the untyped out takes any variable, and only a '
      + 'local is checked for escapes and reads after the scope (safe/SPEC.md section 21.1)', [NameOf(E.Params[0])]));
    Exit;
  end;
  VT := TypeOf(D);
  if not ((VT is TPasClassType) and (TPasClassType(VT).ObjKind = okClass)) then
  begin
    Add(E.Params[0], 'S6', Format('Hold(%s, ...): %s is not of a class type; Hold gives it a class reference (safe/'
      + 'SPEC.md section 21.1)', [D.Name, D.Name]));
    Exit;
  end;
  CT := ConstructorClass(E.Params[1], At);
  if CT = nil then
  begin
    Add(E.Params[1], 'S6', Format('Hold(%s, ...): the second argument must be a constructor call %s.Create(...) '
      + '(or of a descendant), so that the scope is the only owner of the new object (safe/SPEC.md section 21.1)',
      [D.Name, VT.Name]));
    Exit;
  end;
  if not IsA(CT, VT) then
  begin
    Add(E.Params[1], 'S6', Format('Hold(%s, %s.Create): %s is a %s, and %s is not one of its descendants: the untyped '
      + 'out would make %s refer to an object of another class (safe/SPEC.md section 21.1)', [D.Name, CT.Name, D.Name,
      VT.Name, CT.Name, D.Name]));
    Exit;
  end;
  FOwned.Get.Add(Format('%s %d', [ExpandFileName(At.SourceFilename), At.SourceLinenumber]));
  Result := D;
end;

{ S17: the stores of the held V that let it outlive its scope. }
procedure THold.Escapes(const V: TPasElement);
var
  I, J: Integer;
  N, D: TPasElement;
  A: TPasImplAssign;
  P: TParamsExpr;
  At: TPasExpr;
  C: TPasType;
begin
  for I := 0 to FBody.Get.Count - 1 do
  begin
    N := TPasElement(FBody.Get[I]);
    if N is TPasImplAssign then
    begin
      A := TPasImplAssign(N);
      if (Ref(Strip(A.right)) = V) and (Strip(A.right) is TPrimitiveExpr)
        and not ((A.left is TPrimitiveExpr) and IsLocal(Ref(A.left))) then
        Add(A.right, 'S17', Format('%s is held by a scope, and it is stored into %s, which may outlive the scope: the '
          + 'object is destroyed when the scope ends; keep it in the scope, or own it with TOwned (safe/SPEC.md '
          + 'section 21.1)', [V.Name, What(A.left)]));
    end
    else if (N is TParamsExpr) and (TParamsExpr(N).Kind = pekFuncParams) then
    begin
      P := TParamsExpr(N);
      if (P.Value is TBinaryExpr) and (TBinaryExpr(P.Value).OpCode = eopSubIdent) then
        D := Ref(TBinaryExpr(P.Value).right)
      else
        D := Ref(P.Value);
      if (D <> nil) and (D.CustomData is TResElDataBuiltInProc)
        and (TResElDataBuiltInProc(D.CustomData).BuiltIn = bfExit) then
      begin
        if (Length(P.Params) = 1) and (Ref(Strip(P.Params[0])) = V) then
          Add(P.Params[0], 'S17', Format('Exit(%s): %s is held by a scope, and the result outlives it: the object is '
            + 'destroyed when the scope ends (safe/SPEC.md section 21.1)', [V.Name, V.Name]));
        Continue;
      end;
      if (D is TPasProcedure) and SameText(D.Name, 'Send') and (D.Parent is TPasType)
        and (SameText(Copy(D.Parent.Name, 1, 5), 'TChan') or SameText(Copy(D.Parent.Name, 1, 9), 'TSafeChan')) then
      begin
        for J := 0 to High(P.Params) do
          if Ref(Strip(P.Params[J])) = V then
            Add(P.Params[J], 'S17', Format('%s is held by a scope, and it is sent to a channel: it leaves its '
              + 'goroutine, and the object is destroyed when the scope ends; send a copy (a record, a String) '
              + '(safe/SPEC.md section 21.1)', [V.Name]));
        Continue;
      end;
      C := ConstructorClass(P, At);
      if (C <> nil) and Descends(C, 'TTask') then
        for J := 0 to High(P.Params) do
          if Ref(Strip(P.Params[J])) = V then
            Add(P.Params[J], 'S17', Format('%s is held by a scope, and it is passed to the constructor of the task %s, '
              + 'which may keep it after the scope ends and the object is destroyed; pass a copy (safe/SPEC.md '
              + 'section 21.1)', [V.Name, C.Name]));
    end;
  end;
end;

{ E is a call (or a call without parentheses) of one of Names (' reset release ') on the variable Recv. }
function THold.IsCallOn(const E: TPasElement; const Recv: TPasElement; const Names: String): Boolean;
var
  D: TPasElement;
begin
  Result := False;
  if not ((E is TBinaryExpr) and (TBinaryExpr(E).OpCode = eopSubIdent)) then
    Exit;
  D := Ref(TBinaryExpr(E).right);
  Result := (D is TPasProcedure) and (Pos(' ' + LowerCase(D.Name) + ' ', Names) > 0)
    and (TBinaryExpr(E).left is TPrimitiveExpr) and (Ref(TBinaryExpr(E).left) = Recv);
end;

{ The loop for S in Scope with the variable Recv whose body holds Call, or nil. }
function THold.ScopeLoop(const Call: TParamsExpr; const Recv: TPasElement): TPasImplForLoop;
var
  I: Integer;
  N: TPasElement;
  T: TPasType;
begin
  Result := nil;
  for I := 0 to FBody.Get.Count - 1 do
  begin
    N := TPasElement(FBody.Get[I]);
    if not ((N is TPasImplForLoop) and (TPasImplForLoop(N).LoopType = ltIn)
      and (Ref(TPasImplForLoop(N).VariableName) = Recv)) then
      Continue;
    T := TypeOf(TPasImplForLoop(N).StartExpr);
    if (T = nil) or not SameText(T.Name, 'TScopes') or (TPasImplForLoop(N).Body = nil) then
      Continue;
    FNodes.Get.Clear;
    TPasImplForLoop(N).Body.ForEachCall(@Collect, nil);
    if FNodes.Get.IndexOf(Call) >= 0 then
      Result := TPasImplForLoop(N); // the innermost one is the last one found: an inner loop comes after the outer
  end;
end;

{ The last line of El and of what it holds. }
function THold.LastRow(const El: TPasElement): Integer;
var
  I: Integer;
begin
  FNodes.Get.Clear;
  El.ForEachCall(@Collect, nil);
  Result := El.SourceLinenumber;
  for I := 0 to FNodes.Get.Count - 1 do
    if TPasElement(FNodes.Get[I]).SourceLinenumber > Result then
      Result := TPasElement(FNodes.Get[I]).SourceLinenumber;
end;

{ E assigns V again: V := ..., or a Hold(V, ...). }
function THold.Assigns(const E: TPasElement; const V: TPasElement): Boolean;
var
  Recv: TPasExpr;
begin
  Result := ((E is TPasImplAssign) and (TPasImplAssign(E).left is TPrimitiveExpr)
    and (Ref(TPasImplAssign(E).left) = V))
    or ((E is TParamsExpr) and IsHold(TParamsExpr(E), Recv) and (Length(TParamsExpr(E).Params) > 0)
    and (Ref(TParamsExpr(E).Params[0]) = V));
end;

{ S17: the reads of V on the lines after Kill, up to the line where V is assigned again. }
procedure THold.ReadsAfter(const V: TPasElement; const Kill: Integer; const Why: String);
var
  I, Again: Integer;
  N: TPasElement;
  Target: TListBox;
begin
  Again := MaxInt;
  Target := TListBox.Own(TFPList.Create);
  for I := 0 to FBody.Get.Count - 1 do
  begin
    N := TPasElement(FBody.Get[I]);
    if N is TPasImplAssign then
      Target.Get.Add(TPasImplAssign(N).left);
    if (N.SourceLinenumber > Kill) and (N.SourceLinenumber < Again) and Assigns(N, V) then
      Again := N.SourceLinenumber;
  end;
  for I := 0 to FBody.Get.Count - 1 do
  begin
    N := TPasElement(FBody.Get[I]);
    if (N is TPrimitiveExpr) and (Ref(N) = V) and (N.SourceLinenumber > Kill) and (N.SourceLinenumber < Again)
      and (Target.Get.IndexOf(N) < 0) then
      Add(N, 'S17', Format('%s is used after %s, which destroyed the object it holds (Hold): use it inside the scope, '
        + 'or assign it again first (safe/SPEC.md section 21.1)', [V.Name, Why]));
  end;
end;

{ S17: the reads of the held V after its scope. Recv: the receiver of the Hold Call. }
procedure THold.After(const Call: TParamsExpr; const Recv: TPasExpr; const V: TPasElement);
var
  R: TPasElement;
  T: TPasType;
  L: TPasImplForLoop;
  I, Kill: Integer;
  N: TPasElement;
  Why: String;
begin
  if not (Recv is TPrimitiveExpr) then
    Exit;
  R := Ref(Recv);
  T := TypeOf(R);
  if (T = nil) or (R is TPasArgument) then
    Exit; // a handle or a region of the caller lives longer than this routine
  if SameText(T.Name, 'TScopeRef') then
  begin
    L := ScopeLoop(Call, R);
    if L = nil then
    begin
      if IsLocal(R) then
        Add(Call, 'S17', Format('%s.Hold outside the loop for %s in Scope: the handle of a scope is used only in the '
          + 'block of its loop (safe/SPEC.md section 21.1)', [R.Name, R.Name]));
      Exit;
    end;
    ReadsAfter(V, LastRow(L), Format('the end of the scope of %s (for %s in Scope)', [R.Name, R.Name]));
  end
  else if SameText(T.Name, 'TRegion') then
  begin
    // the first Reset, Release or new Create of the region on a later line
    Kill := MaxInt;
    Why := '';
    for I := 0 to FBody.Get.Count - 1 do
    begin
      N := TPasElement(FBody.Get[I]);
      if (N.SourceLinenumber > Call.SourceLinenumber) and (N.SourceLinenumber < Kill)
        and (IsCallOn(N, R, ' reset release ') or ((N is TPasImplAssign) and (TPasImplAssign(N).left is TPrimitiveExpr)
        and (Ref(TPasImplAssign(N).left) = R))) then
      begin
        Kill := N.SourceLinenumber;
        if N is TPasImplAssign then
          Why := Format('%s := TRegion.Create', [R.Name])
        else
          Why := Format('%s.%s', [R.Name, NameOf(N)]);
      end;
    end;
    if Kill < MaxInt then
      ReadsAfter(V, Kill, Why);
  end;
end;

{ ---------- the tree of TComponent (safe/SPEC.md §21.4) ---------- }

{ C is a component class: it or an ancestor is Classes.TComponent or a class TComponent of the checked module. }
function THold.IsComponent(const C: TPasType): Boolean;
var
  X: TPasType;
  M: TPasModule;
  Depth: Integer;
begin
  X := C;
  Depth := 0;
  while (X is TPasClassType) and (TPasClassType(X).ObjKind = okClass) and (Depth < 64) do
  begin
    if SameText(X.Name, 'TComponent') then
    begin
      M := X.GetModule;
      if (M = FModule) or ((M <> nil) and SameText(M.Name, 'Classes')) then
        Exit(True);
    end;
    if TPasClassType(X).AncestorType = nil then
      Break;
    X := TypeOf(TPasClassType(X).AncestorType);
    Inc(Depth);
  end;
  Result := False;
end;

{ E is an owned call: TFoo.Create(AOwner, ...) of a component class whose constructor takes a component first, and
  AOwner is a class instance (not nil, not a class). }
function THold.OwnedCall(const E: TPasExpr): Boolean;
var
  V: TPasExpr;
  At: TPasExpr;
  C: TPasElement;
  P: TPasProcedureType;
begin
  Result := False;
  if not ((E is TParamsExpr) and (TParamsExpr(E).Kind = pekFuncParams) and (Length(TParamsExpr(E).Params) > 0)) then
    Exit;
  if not IsComponent(ConstructorClass(E, At)) then
    Exit;
  V := TParamsExpr(E).Value;
  C := Ref(TBinaryExpr(V).right);
  P := TPasProcedure(C).ProcType;
  if (P = nil) or (P.Args.Count = 0) or not IsComponent(TypeOf(TPasArgument(P.Args[0]).ArgType)) then
    Exit;
  V := TParamsExpr(E).Params[0];
  if (V is TNilExpr) or (Ref(V) is TPasType) then
    Exit;
  Result := IsComponent(TypeOf(V));
end;

{ The routine that the call P calls, or nil. }
function THold.Callee(const P: TParamsExpr): TPasElement;
begin
  if (P.Value is TBinaryExpr) and (TBinaryExpr(P.Value).OpCode = eopSubIdent) then
    Result := Ref(TBinaryExpr(P.Value).right)
  else
    Result := Ref(P.Value);
end;

{ P calls Own of a TOwned, Share of a TShared or Adopt of a TArena or a TArenaRef. }
function THold.IsOwnerCall(const P: TParamsExpr): Boolean;
var
  D: TPasElement;
  N: String;
begin
  Result := False;
  if P.Kind <> pekFuncParams then
    Exit;
  D := Callee(P);
  if not (D is TPasProcedure) or (D.Parent = nil) then
    Exit;
  N := LowerCase(D.Name);
  Result := ((N = 'own') and SameText(Copy(D.Parent.Name, 1, 6), 'TOwned'))
    or ((N = 'share') and SameText(Copy(D.Parent.Name, 1, 7), 'TShared'))
    or ((N = 'adopt') and SameText(Copy(D.Parent.Name, 1, 6), 'TArena'));
end;

{ The constructor call E goes at once into an owner: an argument of Own, Share, Adopt, Go or Hold, or raised. }
function THold.OwnedByShape(const E: TPasElement): Boolean;
var
  P: TPasElement;
  D: TPasElement;
  Recv: TPasExpr;
begin
  P := E.Parent;
  if P is TPasImplRaise then
    Exit(True);
  if not ((P is TParamsExpr) and (TParamsExpr(P).Kind = pekFuncParams) and (TParamsExpr(P).Value <> E)) then
    Exit(False);
  D := Callee(TParamsExpr(P));
  Result := IsOwnerCall(TParamsExpr(P)) or IsHold(TParamsExpr(P), Recv)
    or ((D is TPasProcedure) and SameText(D.Name, 'Go'));
end;

{ The variable that E names (X, Self.X, Obj.X, without casts), or nil. }
function THold.Named(const E: TPasExpr): TPasElement;
var
  X: TPasExpr;
begin
  X := Strip(E);
  if (X is TBinaryExpr) and (TBinaryExpr(X).OpCode = eopSubIdent) then
    X := TBinaryExpr(X).right;
  Result := nil;
  if X is TPrimitiveExpr then
    Result := Ref(X);
  if not (Result is TPasVariable) or (Result is TPasConst) or (Result is TPasProperty) then
    Result := nil;
end;

{ D holds a component owned by its owner on the line Row: a published component field, or the last assignment of D in
  the body on Row or before stores an owned call. }
function THold.OwnedVar(const D: TPasElement; const Row: Integer): Boolean;
var
  I, Last: Integer;
  N: TPasElement;
begin
  Result := False;
  if D = nil then
    Exit;
  if FFields.Get.IndexOf(D) >= 0 then
    Exit(True);
  Last := 0;
  for I := 0 to FBody.Get.Count - 1 do
  begin
    N := TPasElement(FBody.Get[I]);
    if (N is TPasImplAssign) and (TPasImplAssign(N).Kind = akDefault) and (N.SourceLinenumber <= Row)
      and (N.SourceLinenumber >= Last) and (Named(TPasImplAssign(N).left) = D) then
    begin
      Last := N.SourceLinenumber;
      Result := OwnedCall(Strip(TPasImplAssign(N).right));
    end;
  end;
end;

function THold.Key(const Rule: String; const El: TPasElement): String;
begin
  Result := Format('%s %s %d', [Rule, ExpandFileName(El.SourceFilename), El.SourceLinenumber]);
end;

procedure THold.Destroyed(const At: TPasElement; const D: TPasElement; const How: String);
begin
  Add(At, 'S17', Format('%s: %s refers to a component that its Owner destroys (TFoo.Create(AOwner), or a published '
    + 'component field); the owner and the fields of the form still refer to it: leave it to the owner, or create it '
    + 'with Create(nil) and own it with TOwned (safe/SPEC.md section 21.4)', [How, D.Name]));
end;

procedure THold.Twice(const At: TPasExpr; const Owner: String);
begin
  Add(At, 'S17', Format('%s: the component already has an owner (its Owner, the argument of TFoo.Create(AOwner)), '
    + 'and both would destroy it: create it with Create(nil) for %s, or leave it to the owner (safe/SPEC.md section '
    + '21.4)', [Owner, Owner]));
end;

{ The published component fields of the component classes in L (and in the classes nested in them): no S5 there. }
procedure THold.CollectFields(const L: TFPList);
var
  I, J: Integer;
  E, M: TPasElement;
begin
  if L = nil then
    Exit;
  for I := 0 to L.Count - 1 do
  begin
    E := TPasElement(L[I]);
    if not (E is TPasClassType) then
      Continue;
    CollectFields(TPasClassType(E).Members);
    if (TPasClassType(E).ObjKind <> okClass) or not IsComponent(TPasClassType(E)) then
      Continue;
    for J := 0 to TPasClassType(E).Members.Count - 1 do
    begin
      M := TPasElement(TPasClassType(E).Members[J]);
      if (M.ClassType = TPasVariable) and (M.Visibility = visPublished) and IsComponent(TypeOf(M)) then
      begin
        FFields.Get.Add(M);
        FDrop.Get.Add(Key('S5', M));
      end;
    end;
  end;
end;

{ S6 and S17 of the component tree in the statements of Body. }
procedure THold.CheckComponents(const Body: TPasElement);
var
  I, J: Integer;
  N, D: TPasElement;
  P: TParamsExpr;
  Recv, At: TPasExpr;
  Mixed: TLinesBox;
  Owned: TLinesBox;
begin
  if Body = nil then
    Exit;
  FNodes.Get.Clear;
  Body.ForEachCall(@Collect, nil);
  FBody.Get.Assign(FNodes.Get);
  Mixed := TLinesBox.Own(TStringList.Create);
  Mixed.Get.Sorted := True;
  Mixed.Get.Duplicates := dupIgnore;
  Owned := TLinesBox.Own(TStringList.Create);
  Owned.Get.Sorted := True;
  Owned.Get.Duplicates := dupIgnore;
  for I := 0 to FBody.Get.Count - 1 do
  begin
    N := TPasElement(FBody.Get[I]);
    // a constructor call, with or without parentheses (not the TFoo.Create part of TFoo.Create(...))
    if ((N is TParamsExpr) or ((N is TBinaryExpr) and not ((N.Parent is TParamsExpr)
      and (TParamsExpr(N.Parent).Value = N)))) and (ConstructorClass(TPasExpr(N), At) <> nil) then
    begin
      if OwnedCall(TPasExpr(N)) then
        Owned.Get.Add(Key('S6', N))
      else if not OwnedByShape(N) then
        Mixed.Get.Add(Key('S6', N));
    end;
    if (N is TBinaryExpr) and (TBinaryExpr(N).OpCode = eopSubIdent) and SameText(NameOf(TBinaryExpr(N).right), 'Free')
      then
    begin
      D := Named(TBinaryExpr(N).left);
      if OwnedVar(D, N.SourceLinenumber) then
        Destroyed(TBinaryExpr(N).right, D, Format('%s.Free', [D.Name]))
      else if OwnedCall(Strip(TBinaryExpr(N).left)) then
        Twice(TBinaryExpr(N).right, '.Free');
    end;
    if not ((N is TParamsExpr) and (TParamsExpr(N).Kind = pekFuncParams)) then
      Continue;
    P := TParamsExpr(N);
    D := Callee(P);
    if (D is TPasProcedure) and SameText(D.Name, 'FreeAndNil') and (Length(P.Params) = 1) then
    begin
      D := Named(P.Params[0]);
      if OwnedVar(D, P.SourceLinenumber) then
        Destroyed(P.Value, D, Format('FreeAndNil(%s)', [D.Name]));
    end
    else if IsOwnerCall(P) then
    begin
      for J := 0 to High(P.Params) do
        if OwnedCall(Strip(P.Params[J])) then
          Twice(P.Params[J], NameOf(P.Value))
        else if OwnedVar(Named(P.Params[J]), P.SourceLinenumber) then
          Twice(P.Params[J], Format('%s(%s)', [NameOf(P.Value), Named(P.Params[J]).Name]));
    end
    else if IsHold(P, Recv) and (Length(P.Params) = 2) and OwnedCall(Strip(P.Params[1])) then
      Twice(P.Params[1], 'Hold');
  end;
  for I := 0 to Owned.Get.Count - 1 do
    if Mixed.Get.IndexOf(Owned.Get[I]) < 0 then
      FDrop.Get.Add(Owned.Get[I]);
end;

procedure THold.CheckComponentDecls(const Decls: TPasDeclarations);
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
      CheckComponents(TPasProcedure(D).Body.Body);
      CheckComponentDecls(TPasProcedure(D).Body);
    end;
  end;
end;

{ P calls Ref of a specialization of TMap (the resolver names it TMap$G1 or TMap<...>) }
function THold.IsMapRef(const P: TParamsExpr): Boolean;
var
  D: TPasElement;
begin
  D := Callee(P);
  Result := (D is TPasProcedure) and SameText(D.Name, 'Ref') and (D.Parent is TPasRecordType)
    and (SameText(Copy(D.Parent.Name, 1, 5), 'TMap<') or SameText(Copy(D.Parent.Name, 1, 5), 'TMap$'));
end;

procedure THold.CheckProc(const P: TPasProcedure);
var
  I: Integer;
  N, V: TPasElement;
  Recv: TPasExpr;
  Holds: TListBox;
begin
  if (P.Body = nil) or (P.Body.Body = nil) then
    Exit;
  FProc := P;
  FNodes.Get.Clear;
  P.Body.Body.ForEachCall(@Collect, nil);
  FBody.Get.Assign(FNodes.Get);
  Holds := TListBox.Own(TFPList.Create);
  for I := 0 to FBody.Get.Count - 1 do
  begin
    N := TPasElement(FBody.Get[I]);
    if (N is TParamsExpr) and IsHold(TParamsExpr(N), Recv) then
      Holds.Get.Add(N);
    if (N is TParamsExpr) and IsMapRef(TParamsExpr(N))
      and not ((N.Parent is TUnaryExpr) and (TUnaryExpr(N.Parent).OpCode = eopDeref)) then
      Add(N, 'S27', 'the result of Ref of a TMap is kept: the next change of the map may move the place; use it at '
        + 'once as M.Ref(K, D)^ (safe/SPEC.md, section 25.3)');
  end;
  for I := 0 to Holds.Get.Count - 1 do
  begin
    N := TPasElement(Holds.Get[I]);
    IsHold(TParamsExpr(N), Recv);
    V := Shape(TParamsExpr(N));
    if V = nil then
      Continue;
    Escapes(V);
    After(TParamsExpr(N), Recv, V);
  end;
end;

procedure THold.CheckDecls(const Decls: TPasDeclarations);
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
      CheckProc(TPasProcedure(D));
      CheckDecls(TPasProcedure(D).Body);
    end;
  end;
end;

{ Adds the findings to Report and drops the untyped S6 findings on the rows of the constructor calls of valid Holds,
  and the S5 and S6 findings that the component tree answers. }
procedure THold.Flush(var Report: TVetReport);
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(Report.Findings) do
    with Report.Findings[I] do
      if not (((Rule = 'S6') and (FOwned.Get.IndexOf(Format('%s %d', [ExpandFileName(FileName), Row])) >= 0))
        or (FDrop.Get.IndexOf(Format('%s %s %d', [Rule, ExpandFileName(FileName), Row])) >= 0)) then
      begin
        Report.Findings[N] := Report.Findings[I];
        Inc(N);
      end;
  SetLength(Report.Findings, N);
  for I := 0 to High(FReport.Findings) do
    with FReport.Findings[I] do
      VetAdd(Report, FileName, Row, Col, Severity, Rule, Msg);
end;

procedure VetCheckHold(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);
var
  H: THoldBox;
  I: Integer;
begin
  for I := 0 to High(Src.Lines) do
    if Pos('// UNSAFE-UNIT:', Src.Lines[I]) = 1 then
      Exit;
  H := THoldBox.Own(THold.Create(Src, Resolver, Module));
  H.Get.CheckDecls(Module.InterfaceSection);
  H.Get.CheckDecls(Module.ImplementationSection);
  if Module is TPasProgram then
    H.Get.CheckDecls(TPasProgram(Module).ProgramSection);
  if Module.InterfaceSection <> nil then
    H.Get.CollectFields(Module.InterfaceSection.Declarations);
  if Module.ImplementationSection <> nil then
    H.Get.CollectFields(Module.ImplementationSection.Declarations);
  if Module is TPasProgram then
    H.Get.CollectFields(TPasProgram(Module).ProgramSection.Declarations);
  H.Get.CheckComponentDecls(Module.InterfaceSection);
  H.Get.CheckComponentDecls(Module.ImplementationSection);
  if Module is TPasProgram then
    H.Get.CheckComponentDecls(TPasProgram(Module).ProgramSection);
  H.Get.CheckComponents(Module.InitializationSection);
  H.Get.CheckComponents(Module.FinalizationSection);
  H.Get.Flush(Report);
end;

end.
