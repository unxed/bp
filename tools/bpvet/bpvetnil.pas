{ SPDX-License-Identifier: MIT }
{ bpvet rules for nil references (safe/SPEC.md §22.9, the hole H19 of §8). They run in the typed mode on a module that
  resolved (bpvettyped.pas):
    S26a  definite assignment: FPC zeroes only managed types, so a local of a class type, the result of a function of a
          class type and an out parameter of a class type hold garbage, not nil, until they are assigned. Each is
          assigned on every path before it is read, and the result and the out parameter before the routine returns.
          Branches are joined (assigned in all of them), a loop body may not run (unless it is repeat or a for loop
          with constant bounds in its direction), a handler of try...except starts from the state before try. A var
          argument, an address (@F) and a name that a nested routine uses count as assignments;
    S26b  an instance of a class is at most 64 KiB (its fields counted from below): every field of a nil reference then
          lies in the unmapped first pages, and reading it is an exception, not a read of foreign memory.
  A finding with // UNSAFE: <why> on its line (or in a comment block right above) is not reported; a // UNSAFE-UNIT:
  module is not checked. }
unit BpvetNil;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, PasTree, PasResolveEval, PasResolver, BpvetCore, Safe;

procedure VetCheckNil(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);

implementation

type
  TLinesBox = specialize TOwned<TStringList>;
  TListBox = specialize TOwned<TFPList>;

  { The state of a path is a string with one character per tracked reference: '1' assigned, '0' maybe not. A path that
    left (Exit, raise, Break) is all '1': it joins nothing. }
  TNil = class
  private
    FSrc: TVetSource;
    FResolver: TPasResolver;  // borrow: the resolver of the checked module, alive during the check
    FReport: TVetReport;
    FLines: TLinesBox;        // name=file for the sources of include files
    FSeen: TLinesBox;
    FNodes: TListBox;         // the elements of the expression being checked
    FVars: TListBox;          // the tracked declarations (the ones of a declaration and of its implementation both)
    FSlots: array of Integer; // the slot of each of FVars in the state
    FWhat: TLinesBox;         // per slot: how a message names it
    FReturns: String;         // per slot: '1' when it must be assigned when the routine returns
    FState: String;
    FJump: String;            // the join of the paths that left the innermost loop by Break or Continue
    FReported: String;        // per slot: '1' once reported in this routine
    FProc: TPasProcedure;     // borrow: the routine being checked
    procedure Collect(El: TPasElement; Arg: Pointer);
    function Ref(const E: TPasElement): TPasElement;
    function TypeOf(const E: TPasElement): TPasType;
    function LineOf(const FileName: String; const Row: Integer): String;
    function Marked(const El: TPasElement): Boolean;
    procedure Add(const El: TPasElement; const Rule, Msg: String);
    function IsRef(const T: TPasType): Boolean;
    procedure Track(const D, Alias: TPasElement; const What: String; const Returns: Boolean);
    function Slot(const E: TPasElement): Integer;
    function Top: String;
    function Meet(const A, B: String): String;
    function Join(const A, B: String): String;
    function BuiltIn(const E: TPasExpr): String;
    function Callee(const V: TPasExpr): TPasProcedureType;
    procedure Read(const At: TPasElement; const K: Integer);
    procedure Expr(const E: TPasExpr);
    procedure Returning(const At: TPasElement);
    procedure Simple(const E: TPasExpr);
    procedure Loop(const Body: TPasImplElement);
    function ConstInt(const E: TPasExpr; out V: Int64): Boolean;
    function Runs(const F: TPasImplForLoop): Boolean;
    procedure Block(const B: TPasImplBlock);
    procedure TryBlock(const T: TPasImplTry);
    procedure Stmt(const El: TPasImplElement);
    function FieldsSize(const Members: TFPList; const Depth: Integer): Int64;
    function TypeSize(const T: TPasType; const Depth: Integer): Int64;
  public
    constructor Create(const ASrc: TVetSource; const AResolver: TPasResolver);
    procedure CheckProc(const P: TPasProcedure);
    procedure CheckDecls(const Decls: TPasDeclarations);
    procedure CheckClasses(const Decls: TPasDeclarations);
  end;

  TNilBox = specialize TOwned<TNil>;

const
  MaxDepth = 8;
  { a class instance at most this large: the first 64 KiB of the address space are not mapped (safe/SPEC.md §22.9) }
  MaxInstance = 65536;

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

constructor TNil.Create(const ASrc: TVetSource; const AResolver: TPasResolver);
begin
  inherited Create;
  FSrc := ASrc;
  // borrow: the resolver outlives the check (VetResolve)
  FResolver := AResolver;
  FLines := TLinesBox.Own(TStringList.Create);
  FLines.Get.OwnsObjects := True;
  FSeen := TLinesBox.Own(TStringList.Create);
  FSeen.Get.Sorted := True;
  FNodes := TListBox.Own(TFPList.Create);
  FVars := TListBox.Own(TFPList.Create);
  FWhat := TLinesBox.Own(TStringList.Create);
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure TNil.Collect(El: TPasElement; Arg: Pointer);
begin
  FNodes.Get.Add(El);
end;

function TNil.Ref(const E: TPasElement): TPasElement;
begin
  Result := nil;
  if (E <> nil) and (E.CustomData is TResolvedReference) then
    Result := TResolvedReference(E.CustomData).Declaration;
end;

function TNil.TypeOf(const E: TPasElement): TPasType;
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

function TNil.LineOf(const FileName: String; const Row: Integer): String;
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
function TNil.Marked(const El: TPasElement): Boolean;
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

procedure TNil.Add(const El: TPasElement; const Rule, Msg: String);
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

{ ---------- S26a ---------- }

{ T is a reference that FPC does not zero: a class or a class of a class (an interface and a string are managed). }
function TNil.IsRef(const T: TPasType): Boolean;
begin
  Result := ((T is TPasClassType) and (TPasClassType(T).ObjKind = okClass)) or (T is TPasClassOfType);
end;

{ Tracks D in a new slot; Alias (the same thing in the implementation of a routine declared before) shares it. }
procedure TNil.Track(const D, Alias: TPasElement; const What: String; const Returns: Boolean);
var
  K: Integer;
begin
  K := FWhat.Get.Count;
  FWhat.Get.Add(What);
  FReturns := FReturns + Chr(Ord('0') + Ord(Returns));
  FVars.Get.Add(D);
  SetLength(FSlots, Length(FSlots) + 1);
  FSlots[High(FSlots)] := K;
  if (Alias <> nil) and (Alias <> D) then
  begin
    FVars.Get.Add(Alias);
    SetLength(FSlots, Length(FSlots) + 1);
    FSlots[High(FSlots)] := K;
  end;
end;

{ The slot of the tracked reference that E names, or -1. }
function TNil.Slot(const E: TPasElement): Integer;
var
  I: Integer;
begin
  Result := -1;
  if not (E is TPrimitiveExpr) or (TPrimitiveExpr(E).Kind <> pekIdent) then
    Exit;
  I := FVars.Get.IndexOf(Ref(E));
  if I >= 0 then
    Result := FSlots[I];
end;

function TNil.Top: String;
begin
  Result := StringOfChar('1', FWhat.Get.Count);
end;

function TNil.Meet(const A, B: String): String;
var
  I: Integer;
begin
  Result := A;
  for I := 1 to Length(Result) do
    if B[I] = '0' then
      Result[I] := '0';
end;

function TNil.Join(const A, B: String): String;
var
  I: Integer;
begin
  Result := A;
  for I := 1 to Length(Result) do
    if B[I] = '1' then
      Result[I] := '1';
end;

{ The lower-case name of the built-in routine that the statement E calls (exit, break, continue, halt), or ''. }
function TNil.BuiltIn(const E: TPasExpr): String;
var
  V: TPasExpr;
  D: TPasElement;
begin
  Result := '';
  V := E;
  if V is TParamsExpr then
    V := TParamsExpr(V).Value;
  if not (V is TPrimitiveExpr) then
    Exit;
  D := Ref(V);
  if (D <> nil) and (D.CustomData is TResElDataBuiltInProc) then
    case TResElDataBuiltInProc(D.CustomData).BuiltIn of
      bfExit: Result := 'exit';
      bfBreak: Result := 'break';
      bfContinue: Result := 'continue';
    end
  else if (D is TPasProcedure) and SameText(D.Name, 'Halt') then
    Result := 'halt';
end;

{ The type of the routine that a call of V calls: a routine or a variable of a procedural type; nil for a built-in. }
function TNil.Callee(const V: TPasExpr): TPasProcedureType;
var
  D: TPasElement;
  T: TPasType;
begin
  Result := nil;
  if (V is TBinaryExpr) and (TBinaryExpr(V).OpCode = eopSubIdent) then
    D := Ref(TBinaryExpr(V).right)
  else
    D := Ref(V);
  if D is TPasProcedure then
    Exit(TPasProcedure(D).ProcType);
  if (D is TPasVariable) or (D is TPasArgument) then
  begin
    T := TypeOf(D);
    if T is TPasProcedureType then
      Result := TPasProcedureType(T);
  end;
end;

procedure TNil.Read(const At: TPasElement; const K: Integer);
begin
  if (FState[K + 1] = '1') or (FReported[K + 1] = '1') then
    Exit;
  FReported[K + 1] := '1';
  Add(At, 'S26a', Format('%s may be read before it is assigned: FPC does not zero it, so on some path it holds garbage, '
    + 'not nil (safe/SPEC.md section 22.9); assign it on every path before this read (nil if there is nothing yet)',
    [FWhat.Get[K]]));
end;

{ The reads of E are checked; a var or out argument and an address (@F) assign. }
procedure TNil.Expr(const E: TPasExpr);
var
  Writes: String;
  I, J, K: Integer;
  N: TPasElement;
  Params: TParamsExpr;
  T: TPasProcedureType;
  Nodes: TListBox;
begin
  if (E = nil) or (FWhat.Get.Count = 0) then
    Exit;
  FNodes.Get.Clear;
  E.ForEachCall(@Collect, nil);
  Nodes := TListBox.Own(TFPList.Create);
  Nodes.Get.Assign(FNodes.Get);
  begin
    Writes := StringOfChar('0', FWhat.Get.Count);
    for I := 0 to Nodes.Get.Count - 1 do
    begin
      N := TPasElement(Nodes.Get[I]);
      if (N is TParamsExpr) and (TParamsExpr(N).Kind = pekFuncParams) then
      begin
        Params := TParamsExpr(N);
        T := Callee(Params.Value);
        if T <> nil then
          for J := 0 to High(Params.Params) do
            if (J < T.Args.Count) and (TPasArgument(T.Args[J]).Access in [argVar, argOut]) then
            begin
              K := Slot(Params.Params[J]);
              if K >= 0 then
                Writes[K + 1] := '1';
            end;
      end
      else if (N is TUnaryExpr) and (TUnaryExpr(N).OpCode = eopAddress) then
      begin
        K := Slot(TUnaryExpr(N).Operand);
        if K >= 0 then
          Writes[K + 1] := '1';
      end;
    end;
    for I := 0 to Nodes.Get.Count - 1 do
    begin
      K := Slot(TPasElement(Nodes.Get[I]));
      if (K >= 0) and (Writes[K + 1] = '0') then
        Read(TPasElement(Nodes.Get[I]), K);
    end;
  end;
  FState := Join(FState, Writes);
end;

{ The routine returns here: the result and the out parameters are assigned. }
procedure TNil.Returning(const At: TPasElement);
var
  K: Integer;
begin
  for K := 0 to FWhat.Get.Count - 1 do
    if (FReturns[K + 1] = '1') and (FState[K + 1] = '0') and (FReported[K + 1] = '0') then
    begin
      FReported[K + 1] := '1';
      Add(At, 'S26a', Format('%s is not assigned on every path before %s returns: the caller gets garbage, not nil '
        + '(safe/SPEC.md section 22.9); assign it on every path (nil if there is nothing)', [FWhat.Get[K], FProc.Name]));
    end;
end;

procedure TNil.Simple(const E: TPasExpr);
var
  K: Integer;
  Name: String;
begin
  Expr(E);
  Name := BuiltIn(E);
  if Name = 'exit' then
  begin
    // Exit(X) assigns the result
    if (E is TParamsExpr) and (Length(TParamsExpr(E).Params) > 0) then
      for K := 0 to FWhat.Get.Count - 1 do
        if Pos('the result', FWhat.Get[K]) = 1 then
          FState[K + 1] := '1';
    Returning(E);
    FState := Top;
  end
  else if (Name = 'break') or (Name = 'continue') then
  begin
    FJump := Meet(FJump, FState);
    FState := Top;
  end
  else if Name = 'halt' then
    FState := Top;
end;

{ The body of while or for: it may not run, so the state after the loop is the one before. }
procedure TNil.Loop(const Body: TPasImplElement);
var
  Before, Jump: String;
begin
  Before := FState;
  Jump := FJump;
  FJump := Top;
  Stmt(Body);
  FJump := Jump;
  FState := Before;
end;

{ E is a constant integer V. }
function TNil.ConstInt(const E: TPasExpr; out V: Int64): Boolean;
var
  R: TResEvalValue;
begin
  Result := False;
  V := 0;
  if E = nil then
    Exit;
  try
    R := FResolver.Eval(E, [refConst], False);
  except
    on Exception do
      Exit;
  end;
  if R = nil then
    Exit;
  if R.Kind = revkInt then
  begin
    V := TResEvalInt(R).Int;
    Result := True;
  end;
  ReleaseEvalValue(R);
end;

{ The body of the for loop F runs at least once: its bounds are constants in its direction (for J := 1 to 1000). }
function TNil.Runs(const F: TPasImplForLoop): Boolean;
var
  A, B: Int64;
begin
  Result := (F.LoopType <> ltIn) and ConstInt(F.StartExpr, A) and ConstInt(F.EndExpr, B)
    and (((F.LoopType = ltNormal) and (A <= B)) or ((F.LoopType = ltDown) and (A >= B)));
end;

procedure TNil.Block(const B: TPasImplBlock);
var
  I: Integer;
begin
  if B = nil then
    Exit;
  for I := 0 to B.Elements.Count - 1 do
    Stmt(TPasImplElement(B.Elements[I]));
end;

{ An exception may come from any statement of the try block, so a handler starts from the state before it. }
procedure TNil.TryBlock(const T: TPasImplTry);
var
  Before, After: String;
  H: TPasImplTryHandler;
  I: Integer;
  HasOn: Boolean;
begin
  Before := FState;
  Block(T);
  H := T.FinallyExcept;
  if H is TPasImplTryFinally then
  begin
    After := FState;
    FState := Before;
    Block(H);
    FState := Join(After, FState);
  end
  else if H is TPasImplTryExcept then
  begin
    After := FState;
    HasOn := False;
    for I := 0 to H.Elements.Count - 1 do
      if TObject(H.Elements[I]) is TPasImplExceptOn then
      begin
        HasOn := True;
        FState := Before;
        Stmt(TPasImplExceptOn(H.Elements[I]).Body);
        After := Meet(After, FState);
      end;
    if not HasOn then
    begin
      FState := Before;
      Block(H);
      After := Meet(After, FState);
    end;
    if T.ElseBranch <> nil then
    begin
      FState := Before;
      Block(T.ElseBranch);
      After := Meet(After, FState);
    end;
    FState := After;
  end;
end;

procedure TNil.Stmt(const El: TPasImplElement);
var
  Before, After: String;
  I, K: Integer;
  C: TPasImplCaseOf;
  A: TPasImplAssign;
  Elem: TPasImplElement;
begin
  if El = nil then
    Exit;
  if El is TPasImplAssign then
  begin
    A := TPasImplAssign(El);
    Expr(A.right);
    K := Slot(A.left);
    if K < 0 then
      Expr(A.left)
    else
    begin
      if A.Kind <> akDefault then
        Read(A.left, K);
      FState[K + 1] := '1';
    end;
  end
  else if El is TPasImplSimple then
    Simple(TPasImplSimple(El).Expr)
  else if El is TPasImplIfElse then
  begin
    Expr(TPasImplIfElse(El).ConditionExpr);
    Before := FState;
    Stmt(TPasImplIfElse(El).IfBranch);
    After := FState;
    FState := Before;
    Stmt(TPasImplIfElse(El).ElseBranch);
    FState := Meet(After, FState);
  end
  else if El is TPasImplWhileDo then
  begin
    Expr(TPasImplWhileDo(El).ConditionExpr);
    Loop(TPasImplWhileDo(El).Body);
  end
  else if El is TPasImplForLoop then
  begin
    Expr(TPasImplForLoop(El).StartExpr);
    Expr(TPasImplForLoop(El).EndExpr);
    Before := FState;
    K := Slot(TPasImplForLoop(El).VariableName);
    if K >= 0 then
      FState[K + 1] := '1';
    if Runs(TPasImplForLoop(El)) then
    begin
      // the body runs at least once, as the body of repeat
      After := FJump;
      FJump := Top;
      Stmt(TPasImplForLoop(El).Body);
      FState := Meet(FState, FJump);
      FJump := After;
    end
    else
    begin
      Loop(TPasImplForLoop(El).Body);
      FState := Before;
    end;
  end
  else if El is TPasImplRepeatUntil then
  begin
    // the body runs at least once; Break and Continue join the state after it
    After := FJump;
    FJump := Top;
    Block(TPasImplBlock(El));
    FState := Meet(FState, FJump);
    FJump := After;
    Expr(TPasImplRepeatUntil(El).ConditionExpr);
  end
  else if El is TPasImplCaseOf then
  begin
    C := TPasImplCaseOf(El);
    Expr(C.CaseExpr);
    Before := FState;
    After := Top;
    for I := 0 to C.Elements.Count - 1 do
    begin
      Elem := TPasImplElement(C.Elements[I]);
      FState := Before;
      if Elem is TPasImplCaseStatement then
        Stmt(TPasImplCaseStatement(Elem).Body)
      else
        Stmt(Elem);
      After := Meet(After, FState);
    end;
    if C.ElseBranch = nil then
      After := Meet(After, Before);
    FState := After;
  end
  else if El is TPasImplTry then
    TryBlock(TPasImplTry(El))
  else if El is TPasImplExceptOn then
    Stmt(TPasImplExceptOn(El).Body)
  else if El is TPasImplRaise then
  begin
    Expr(TPasImplRaise(El).ExceptObject);
    Expr(TPasImplRaise(El).ExceptAddr);
    FState := Top;
  end
  else if El is TPasImplWithDo then
  begin
    for I := 0 to TPasImplWithDo(El).Expressions.Count - 1 do
      Expr(TPasExpr(TPasImplWithDo(El).Expressions[I]));
    Stmt(TPasImplWithDo(El).Body);
  end
  else if El is TPasImplAsmStatement then
    // assembler may assign anything
    FState := Top
  else if El is TPasImplBlock then
    Block(TPasImplBlock(El));
end;

procedure TNil.CheckProc(const P: TPasProcedure);
var
  Decl: TPasProcedure;
  I: Integer;
  D, Alias: TPasElement;
  Nested: TListBox;
begin
  if (P.Body = nil) or (P.Body.Body = nil) then
    Exit;
  FProc := P;
  FVars.Get.Clear;
  SetLength(FSlots, 0);
  FWhat.Get.Clear;
  FReturns := '';
  Decl := P;
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    Decl := TPasProcedureScope(P.CustomData).DeclarationProc;
  if (Decl.ProcType is TPasFunctionType) and IsRef(TypeOf(TPasFunctionType(Decl.ProcType).ResultEl)) then
  begin
    Alias := nil;
    if P.ProcType is TPasFunctionType then
      Alias := TPasFunctionType(P.ProcType).ResultEl;
    Track(TPasFunctionType(Decl.ProcType).ResultEl, Alias, 'the result of ' + P.Name, True);
  end;
  for I := 0 to Decl.ProcType.Args.Count - 1 do
  begin
    D := TPasElement(Decl.ProcType.Args[I]);
    if (TPasArgument(D).Access = argOut) and IsRef(TypeOf(D)) then
    begin
      Alias := nil;
      if I < P.ProcType.Args.Count then
        Alias := TPasElement(P.ProcType.Args[I]);
      Track(D, Alias, 'the out parameter ' + D.Name, True);
    end;
  end;
  for I := 0 to P.Body.Declarations.Count - 1 do
  begin
    D := TPasElement(P.Body.Declarations[I]);
    if (D is TPasVariable) and not (D is TPasConst) and not (D is TPasProperty)
      and (TPasVariable(D).AbsoluteExpr = nil) and IsRef(TypeOf(D)) then
      Track(D, nil, 'the local ' + D.Name, False);
  end;
  if FWhat.Get.Count = 0 then
    Exit;
  FState := StringOfChar('0', FWhat.Get.Count);
  FReported := FState;
  FJump := Top;
  // a name that a nested routine uses counts as assigned: the nested routine may be the one that assigns it
  FNodes.Get.Clear;
  for I := 0 to P.Body.Declarations.Count - 1 do
    if TObject(P.Body.Declarations[I]) is TPasProcedure then
      TPasElement(P.Body.Declarations[I]).ForEachCall(@Collect, nil);
  Nested := TListBox.Own(TFPList.Create);
  Nested.Get.Assign(FNodes.Get);
  begin
    for I := 0 to Nested.Get.Count - 1 do
      if Slot(TPasElement(Nested.Get[I])) >= 0 then
        FState[Slot(TPasElement(Nested.Get[I])) + 1] := '1';
  end;
  Block(P.Body.Body);
  Returning(P);
end;

procedure TNil.CheckDecls(const Decls: TPasDeclarations);
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

{ ---------- S26b ---------- }

{ The size of the fields among Members, from below (no alignment, no variant parts). }
function TNil.FieldsSize(const Members: TFPList; const Depth: Integer): Int64;
var
  I: Integer;
  M: TPasElement;
begin
  Result := 0;
  for I := 0 to Members.Count - 1 do
  begin
    M := TPasElement(Members[I]);
    if (M is TPasVariable) and not (M is TPasConst) and not (M is TPasProperty)
      and not (vmClass in TPasVariable(M).VarModifiers) then
      Inc(Result, TypeSize(TypeOf(M), Depth + 1));
    if Result > High(Int64) div 4 then
      Exit;
  end;
end;

function TNil.TypeSize(const T: TPasType; const Depth: Integer): Int64;
var
  I: Integer;
  N: Int64;
begin
  Result := 0;
  if (T = nil) or (Depth > MaxDepth) then
    Exit;
  if T is TPasClassType then
  begin
    if TPasClassType(T).ObjKind = okObject then
      Exit(FieldsSize(TPasClassType(T).Members, Depth));
    Exit(SizeOf(SizeInt));
  end;
  if T is TPasRecordType then
    Exit(FieldsSize(TPasRecordType(T).Members, Depth));
  if T is TPasArrayType then
  begin
    if Length(TPasArrayType(T).Ranges) = 0 then
      Exit(SizeOf(SizeInt));
    N := 1;
    for I := 0 to High(TPasArrayType(T).Ranges) do
    begin
      try
        N := N * FResolver.GetRangeLength(TPasArrayType(T).Ranges[I]);
      except
        on Exception do
          N := 0;
      end;
      if (N <= 0) or (N > High(Int64) div 65536) then
        Exit(0);
    end;
    Exit(N * TypeSize(TypeOf(TPasArrayType(T).ElType), Depth + 1));
  end;
  if (T is TPasPointerType) or (T is TPasClassOfType) or (T is TPasProcedureType) then
    Exit(SizeOf(SizeInt));
  if T.CustomData is TResElDataBaseType then
    case TResElDataBaseType(T.CustomData).BaseType of
      btChar, btAnsiChar, btBoolean, btByteBool, btByte, btShortInt: Exit(1);
      btWideChar, btWordBool, btWord, btSmallInt: Exit(2);
      btSingle, btLongBool, btLongWord, btLongint, btUIntSingle, btIntSingle: Exit(4);
      btExtended, btCExtended: Exit(10);
      btShortString: Exit(256);
    else
      Exit(SizeOf(SizeInt));
    end;
  // an enumeration, a set, a subrange, a short string of a given length: at least a byte
  Result := 1;
end;

procedure TNil.CheckClasses(const Decls: TPasDeclarations);
var
  I, Depth: Integer;
  D: TPasElement;
  C: TPasType;
  Size: Int64;
begin
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    D := TPasElement(Decls.Declarations[I]);
    if not (D is TPasClassType) or (TPasClassType(D).ObjKind <> okClass) or TPasClassType(D).IsForward then
      Continue;
    // the reference to the VMT, then the fields of the class and of its ancestors
    Size := SizeOf(SizeInt);
    C := TPasType(D);
    Depth := 0;
    while (C is TPasClassType) and (Depth <= MaxDepth) do
    begin
      Inc(Size, FieldsSize(TPasClassType(C).Members, 0));
      C := TypeOf(TPasClassType(C).AncestorType);
      Inc(Depth);
    end;
    if Size > MaxInstance then
      Add(D, 'S26b', Format('an instance of %s is at least %d bytes: a field of a nil reference past the first 64 KiB '
        + 'may lie in mapped memory, so reading it would not fault (safe/SPEC.md section 22.9); keep the large data in '
        + 'a dynamic array field', [D.Name, Size]));
  end;
end;

procedure VetCheckNil(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);
var
  N: TNilBox;
  I: Integer;
begin
  for I := 0 to High(Src.Lines) do
    if Pos('// UNSAFE-UNIT:', Src.Lines[I]) = 1 then
      Exit;
  N := TNilBox.Own(TNil.Create(Src, Resolver));
  N.Get.CheckDecls(Module.InterfaceSection);
  N.Get.CheckDecls(Module.ImplementationSection);
  N.Get.CheckClasses(Module.InterfaceSection);
  N.Get.CheckClasses(Module.ImplementationSection);
  if Module is TPasProgram then
  begin
    N.Get.CheckDecls(TPasProgram(Module).ProgramSection);
    N.Get.CheckClasses(TPasProgram(Module).ProgramSection);
  end;
  for I := 0 to High(N.Get.FReport.Findings) do
    with N.Get.FReport.Findings[I] do
      VetAdd(Report, FileName, Row, Col, Severity, Rule, Msg);
end;

end.
