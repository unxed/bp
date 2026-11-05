{ SPDX-License-Identifier: MIT }
{ bpvet: H20 of S17 (unxed/bp#207), in the typed mode on a module that resolved (bpvettyped.pas). FPC passes a local
  String, dynamic array or interface (or a record that holds one) to a const parameter without a reference, so its count
  stays at 1. When the callee is a nested routine that writes that local of its parent, the write frees what the
  parameter names, and the callee reads freed memory:
    S17  a call of a nested routine that passes a variable of a routine around it (a local, a value parameter or the
         result) of a managed type as a const (or constref) argument, when the nested routine writes that variable,
         itself or through the nested routines it calls (bpvetnested.pas); and a call of a procedure value with such an
         argument once a nested routine that writes the variable is used as a procedure value there.
  A global, a field or a var parameter in the same place is counted by the caller, so it is not a finding. A finding
  with // UNSAFE: <why> on its line (or in a comment block right above) is not reported; a // UNSAFE-UNIT: module is
  not checked. }
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

  TH20 = class
  private
    FSrc: TVetSource;
    FResolver: TPasResolver;  // borrow: the resolver of the checked module, alive during the check
    FReport: TVetReport;
    FSeen: TLinesBox;
    FNodes: TListBox;
    procedure Collect(El: TPasElement; Arg: Pointer);
    function Managed(const T: TPasType; const Depth: Integer): Boolean;
    function IsManagedDecl(const D: TPasElement): Boolean;
    function Marked(const El: TPasElement): Boolean;
    procedure Add(const El: TPasElement; const Msg: String);
    function OwnVar(const O: TPasProcedure; const D: TPasElement): Boolean;
    procedure CheckCalls(const O: TPasProcedure; const N: TVetNested; const Body: TPasImplBlock;
      const Escaped: TFPList);
  public
    constructor Create(const ASrc: TVetSource; const AResolver: TPasResolver);
    procedure CheckRoutine(const O: TPasProcedure);
    procedure CheckDecls(const Decls: TPasDeclarations);
    procedure Flush(var Report: TVetReport);
  end;

  THBox = specialize TOwned<TH20>;

constructor TH20.Create(const ASrc: TVetSource; const AResolver: TPasResolver);
begin
  inherited Create;
  FSrc := ASrc;
  // borrow: the resolver outlives the check (VetResolve)
  FResolver := AResolver;
  FSeen := TLinesBox.Own(TStringList.Create);
  FSeen.Get.Sorted := True;
  FNodes := TListBox.Own(TFPList.Create);
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure TH20.Collect(El: TPasElement; Arg: Pointer);
begin
  FNodes.Get.Add(El);
end;

{ A value of type T holds a reference that a const parameter does not count: a String, a dynamic array, an interface,
  or a record or a static array with one inside. }
function TH20.Managed(const T: TPasType; const Depth: Integer): Boolean;
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

function TH20.IsManagedDecl(const D: TPasElement): Boolean;
var
  R: TPasResolverResult;
begin
  Result := False;
  try
    FResolver.ComputeElement(D, R, []);
  except
    on Exception do
      Exit;
  end;
  Result := (R.BaseType in [btString, btAnsiString, btUnicodeString, btWideString, btRawByteString])
    or Managed(R.LoTypeEl, 0);
end;

{ // UNSAFE: at the end of the line of El or on a comment line right above it (more comment lines may follow). }
function TH20.Marked(const El: TPasElement): Boolean;
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

procedure TH20.Add(const El: TPasElement; const Msg: String);
var
  Row: Integer;
  Seen, Name: String;
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
  Name := El.Name;
  if El is TPrimitiveExpr then
    Name := TPrimitiveExpr(El).Value;
  VetAdd(FReport, FSrc.FileName, Row, VetWordColumn(VetLine(FSrc, Row), Name), vsError, 'S17', Msg);
end;

{ D is a variable of O that a const parameter does not count: a local, a value parameter or the result. }
function TH20.OwnVar(const O: TPasProcedure; const D: TPasElement): Boolean;
begin
  Result := ((D is TPasVariable) and not (D is TPasConst) and not (D is TPasProperty) and (D.Parent = O.Body))
    or ((D is TPasArgument) and (D.Parent = O.ProcType) and (TPasArgument(D).Access = argDefault))
    or ((D is TPasResultElement) and (O.ProcType is TPasFunctionType)
    and (D = TPasFunctionType(O.ProcType).ResultEl));
end;

{ The calls in Body (of O or of a routine nested in it) of the nested routines of O, and of procedure values. }
procedure TH20.CheckCalls(const O: TPasProcedure; const N: TVetNested; const Body: TPasImplBlock;
  const Escaped: TFPList);
var
  Nodes: TListBox;
  I, J, K: Integer;
  P: TParamsExpr;
  C, D: TPasElement;
  PT: TPasProcedureType;
  A: TPasArgument;
  Via: String;
  R: TPasResolverResult;
begin
  Nodes := TListBox.Own(TFPList.Create);
  FNodes.Get.Clear;
  Body.ForEachCall(@Collect, nil);
  Nodes.Get.Assign(FNodes.Get);
  for I := 0 to Nodes.Get.Count - 1 do
  begin
    if not ((TObject(Nodes.Get[I]) is TParamsExpr) and (TParamsExpr(Nodes.Get[I]).Kind = pekFuncParams)) then
      Continue;
    P := TParamsExpr(Nodes.Get[I]);
    C := VetRefOf(P.Value);
    K := -1;
    PT := nil;
    if C is TPasProcedure then
    begin
      K := N.IndexOf(C);
      if K < 0 then
        Continue;
      PT := TPasProcedure(C).ProcType;
      Via := C.Name;
    end
    else if ((C is TPasVariable) or (C is TPasArgument)) and (Escaped.Count > 0) then
    begin
      try
        FResolver.ComputeElement(C, R, []);
      except
        on Exception do
          Continue;
      end;
      if not ((R.LoTypeEl is TPasProcedureType) and TPasProcedureType(R.LoTypeEl).IsNested) then
        Continue;
      PT := TPasProcedureType(R.LoTypeEl);
      Via := 'the procedure value ' + C.Name;
    end
    else
      Continue;
    for J := 0 to High(P.Params) do
    begin
      if J >= PT.Args.Count then
        Break;
      A := TPasArgument(PT.Args[J]);
      if not (A.Access in [argConst, argConstRef]) or not (P.Params[J] is TPrimitiveExpr) then
        Continue;
      D := VetRefOf(P.Params[J]);
      if (D = nil) or not OwnVar(O, D) or not IsManagedDecl(D) then
        Continue;
      if ((K >= 0) and (N.Writes(K).IndexOf(D) >= 0)) or ((K < 0) and (Escaped.IndexOf(D) >= 0)) then
        Add(P.Params[J], Format('H20 (unxed/bp#207): %s is passed to the const parameter %s of %s, which (or a nested '
          + 'routine it calls) writes %s: FPC passes a local String, dynamic array or interface to a const parameter '
          + 'without a reference, so the write frees what %s names and it reads freed memory; make %s a value '
          + 'parameter, or pass a copy', [D.Name, A.Name, Via, D.Name, A.Name, A.Name]));
    end;
  end;
end;

procedure TH20.CheckRoutine(const O: TPasProcedure);
var
  N: specialize TOwned<TVetNested>;
  Escaped, Bodies: TListBox;
  I, J, K: Integer;
  X: TPasElement;
begin
  if (O.Body = nil) or (O.Body.Body = nil) then
    Exit;
  N := specialize TOwned<TVetNested>.Own(TVetNested.Create(O));
  if N.Get.Count = 0 then
    Exit;
  // the bodies where a call may pass a variable of O: O and its nested routines
  Bodies := TListBox.Own(TFPList.Create);
  Bodies.Get.Add(O.Body.Body);
  for I := 0 to N.Get.Count - 1 do
    Bodies.Get.Add(N.Get.Routine(I).Body.Body);
  // the variables written by nested routines used as procedure values
  Escaped := TListBox.Own(TFPList.Create);
  for I := 0 to Bodies.Get.Count - 1 do
  begin
    FNodes.Get.Clear;
    TPasImplBlock(Bodies.Get[I]).ForEachCall(@Collect, nil);
    for J := 0 to FNodes.Get.Count - 1 do
    begin
      X := TPasElement(FNodes.Get[J]);
      if not (X is TPrimitiveExpr) then
        Continue;
      K := N.Get.IndexOf(VetRefOf(X));
      if (K >= 0) and (VetUseOf(X) = 'v') then
        Escaped.Get.Assign(N.Get.Writes(K), laOr);
    end;
  end;
  for I := 0 to Bodies.Get.Count - 1 do
    CheckCalls(O, N.Get, TPasImplBlock(Bodies.Get[I]), Escaped.Get);
end;

procedure TH20.CheckDecls(const Decls: TPasDeclarations);
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
      CheckRoutine(TPasProcedure(D));
      CheckDecls(TPasProcedure(D).Body);
    end;
  end;
end;

procedure TH20.Flush(var Report: TVetReport);
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
  H: THBox;
  I: Integer;
begin
  for I := 0 to High(Src.Lines) do
    if Pos('// UNSAFE-UNIT:', Src.Lines[I]) = 1 then
      Exit;
  H := THBox.Own(TH20.Create(Src, Resolver));
  H.Get.CheckDecls(Module.InterfaceSection);
  H.Get.CheckDecls(Module.ImplementationSection);
  if Module is TPasProgram then
    H.Get.CheckDecls(TPasProgram(Module).ProgramSection);
  H.Get.Flush(Report);
end;

end.
