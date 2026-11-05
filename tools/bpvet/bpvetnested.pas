{ SPDX-License-Identifier: MIT }
{ bpvet: what the nested routines of a routine write and read of the variables around them, through the nested
  routines they call (transitively). S28 (bpvets28.pas) takes a call of a nested routine that writes the String of a
  view as a write of it; H20 of S17 (bpvetsh20.pas) takes it as a write of a variable bound to a const parameter. }
unit BpvetNested;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Contnrs, PasTree, PasResolveEval, PasResolver, Safe;

type
  { The nested routines of a routine (theirs too), with the variables each one writes and names, its own and those of
    the routines around it, through the nested routines it names. }
  TVetNested = class
  private
    FDescs: specialize TOwned<TFPList>;
    FWrites: specialize TOwned<TObjectList>;  // of TFPList: the declarations each one writes
    FRefs: specialize TOwned<TObjectList>;    // of TFPList: the declarations each one names
  public
    constructor Create(const P: TPasProcedure);
    function Count: Integer;
    function Routine(const I: Integer): TPasProcedure;
    function IndexOf(const D: TPasElement): Integer;
    function Writes(const I: Integer): TFPList;
    function Refs(const I: Integer): TFPList;
  end;

{ The declaration that E names, or nil. }
function VetRefOf(const E: TPasElement): TPasElement;
{ The writes of variables among the elements Nodes (of one body): Found gets each node that writes, Decls the variable
  written and Hows how ("S := ...", "SetLength(S)", ...): an assignment to it or to an element of it, a for loop over
  it, its address (@S), and a var or out argument (SetLength, Insert, Delete, SetString, Str, Read, ReadLn by name). }
procedure VetWrites(const Nodes, Found, Decls: TFPList; const Hows: TStringList);
{ How the expression N, which names a routine, uses it: 'c' a call, 'v' a procedure value. }
function VetUseOf(const N: TPasElement): Char;

implementation

type
  TCollector = class
    Nodes: specialize TOwned<TFPList>;
    constructor Create;
    procedure Collect(El: TPasElement; Arg: Pointer);
  end;

constructor TCollector.Create;
begin
  inherited Create;
  Nodes := specialize TOwned<TFPList>.Own(TFPList.Create);
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure TCollector.Collect(El: TPasElement; Arg: Pointer);
begin
  Nodes.Get.Add(El);
end;

function VetRefOf(const E: TPasElement): TPasElement;
begin
  Result := nil;
  if (E <> nil) and (E.CustomData is TResolvedReference) then
    Result := TResolvedReference(E.CustomData).Declaration;
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

procedure AddOne(const D, Node: TPasElement; const How: String; const Found, Decls: TFPList; const Hows: TStringList);
begin
  if not ((D is TPasVariable) or (D is TPasArgument) or (D is TPasResultElement)) then
    Exit;
  Found.Add(Node);
  Decls.Add(D);
  Hows.Add(How);
end;

procedure VetWrites(const Nodes, Found, Decls: TFPList; const Hows: TStringList);
var
  I, J: Integer;
  N, C: TPasElement;
  L: TPasExpr;
  P: TParamsExpr;
  Name: String;
  Hit: Boolean;
begin
  for I := 0 to Nodes.Count - 1 do
  begin
    N := TPasElement(Nodes[I]);
    if N is TPasImplAssign then
    begin
      L := TPasImplAssign(N).left;
      if L is TPrimitiveExpr then
        AddOne(VetRefOf(L), L, NameOf(L) + ' := ...', Found, Decls, Hows)
      else if (L is TParamsExpr) and (TParamsExpr(L).Kind = pekArrayParams)
        and (TParamsExpr(L).Value is TPrimitiveExpr) then
        AddOne(VetRefOf(TParamsExpr(L).Value), L, NameOf(L) + '[...] := ...', Found, Decls, Hows);
    end
    else if (N is TPasImplForLoop) and (TPasImplForLoop(N).VariableName is TPrimitiveExpr) then
      AddOne(VetRefOf(TPasImplForLoop(N).VariableName), TPasImplForLoop(N).VariableName,
        'for ' + NameOf(TPasImplForLoop(N).VariableName), Found, Decls, Hows)
    else if (N is TUnaryExpr) and (TUnaryExpr(N).OpCode = eopAddress)
      and (TUnaryExpr(N).Operand is TPrimitiveExpr) then
      AddOne(VetRefOf(TUnaryExpr(N).Operand), TUnaryExpr(N).Operand,
        '@' + NameOf(TUnaryExpr(N).Operand) + ' (a pointer that)', Found, Decls, Hows)
    else if (N is TParamsExpr) and (TParamsExpr(N).Kind = pekFuncParams) then
    begin
      P := TParamsExpr(N);
      if (P.Value is TBinaryExpr) and (TBinaryExpr(P.Value).OpCode = eopSubIdent) then
        C := VetRefOf(TBinaryExpr(P.Value).right)
      else
        C := VetRefOf(P.Value);
      if C = nil then
        Continue;
      Name := LowerCase(C.Name);
      for J := 0 to High(P.Params) do
      begin
        if not (P.Params[J] is TPrimitiveExpr) then
          Continue;
        Hit := ((J = 0) and ((Name = 'setlength') or (Name = 'uniquestring') or (Name = 'delete')
          or (Name = 'setstring'))) or ((J = 1) and (Name = 'insert'))
          or ((J = High(P.Params)) and (J > 0) and (Name = 'str')) or (Name = 'read') or (Name = 'readln');
        if not Hit and (C is TPasProcedure) and (TPasProcedure(C).ProcType <> nil)
          and (J < TPasProcedure(C).ProcType.Args.Count) then
          Hit := TPasArgument(TPasProcedure(C).ProcType.Args[J]).Access in [argVar, argOut];
        if Hit then
          AddOne(VetRefOf(P.Params[J]), P.Params[J], Format('%s(%s)', [C.Name, NameOf(P.Params[J])]), Found, Decls,
            Hows);
      end;
    end;
  end;
end;

function VetUseOf(const N: TPasElement): Char;
var
  P: TPasElement;
begin
  P := N.Parent;
  if (P is TUnaryExpr) and (TUnaryExpr(P).OpCode = eopAddress) then
    Result := 'v'
  else if (P is TParamsExpr) and (TParamsExpr(P).Value <> N) then
    Result := 'v'
  else if (P is TPasImplAssign) and (TPasImplAssign(P).right = N) then
    Result := 'v'
  else
    Result := 'c';
end;

procedure NestedOf(const P: TPasProcedure; const Descs: TFPList);
var
  I: Integer;
  D: TPasElement;
begin
  if P.Body = nil then
    Exit;
  for I := 0 to P.Body.Declarations.Count - 1 do
  begin
    D := TPasElement(P.Body.Declarations[I]);
    if (D is TPasProcedure) and (TPasProcedure(D).Body <> nil) and (TPasProcedure(D).Body.Body <> nil) then
    begin
      Descs.Add(D);
      NestedOf(TPasProcedure(D), Descs);
    end;
  end;
end;

procedure AddNew(const L: TFPList; const X: Pointer; var Changed: Boolean);
begin
  if L.IndexOf(X) < 0 then
  begin
    L.Add(X);
    Changed := True;
  end;
end;

constructor TVetNested.Create(const P: TPasProcedure);
var
  I, J, K: Integer;
  C: specialize TOwned<TCollector>;
  Found, Hows: specialize TOwned<TFPList>;
  HowText: specialize TOwned<TStringList>;
  W, R: TFPList;
  D: TPasElement;
  Changed: Boolean;
begin
  inherited Create;
  FDescs := specialize TOwned<TFPList>.Own(TFPList.Create);
  FWrites := specialize TOwned<TObjectList>.Own(TObjectList.Create(True));
  FRefs := specialize TOwned<TObjectList>.Own(TObjectList.Create(True));
  NestedOf(P, FDescs.Get);
  if FDescs.Get.Count = 0 then
    Exit;
  C := specialize TOwned<TCollector>.Own(TCollector.Create);
  for I := 0 to FDescs.Get.Count - 1 do
  begin
    C.Get.Nodes.Get.Clear;
    TPasProcedure(FDescs.Get[I]).Body.Body.ForEachCall(@C.Get.Collect, nil);
    // UNSAFE: the list FWrites owns it (OwnsObjects)
    W := TFPList.Create;
    FWrites.Get.Add(W);
    // UNSAFE: the list FRefs owns it (OwnsObjects)
    R := TFPList.Create;
    FRefs.Get.Add(R);
    Found := specialize TOwned<TFPList>.Own(TFPList.Create);
    Hows := specialize TOwned<TFPList>.Own(TFPList.Create);
    HowText := specialize TOwned<TStringList>.Own(TStringList.Create);
    VetWrites(C.Get.Nodes.Get, Found.Get, Hows.Get, HowText.Get);
    Changed := False;
    for J := 0 to Hows.Get.Count - 1 do
      AddNew(W, Hows.Get[J], Changed);
    for J := 0 to C.Get.Nodes.Get.Count - 1 do
      if TObject(C.Get.Nodes.Get[J]) is TPrimitiveExpr then
      begin
        D := VetRefOf(TPasElement(C.Get.Nodes.Get[J]));
        if D <> nil then
          AddNew(R, D, Changed);
      end;
  end;
  // through the nested routines each one names, until nothing grows
  repeat
    Changed := False;
    for I := 0 to FDescs.Get.Count - 1 do
      for J := 0 to FDescs.Get.Count - 1 do
        if (I <> J) and (Refs(I).IndexOf(FDescs.Get[J]) >= 0) then
        begin
          for K := 0 to Writes(J).Count - 1 do
            AddNew(Writes(I), Writes(J)[K], Changed);
          for K := 0 to Refs(J).Count - 1 do
            AddNew(Refs(I), Refs(J)[K], Changed);
        end;
  until not Changed;
end;

function TVetNested.Count: Integer;
begin
  Result := FDescs.Get.Count;
end;

function TVetNested.Routine(const I: Integer): TPasProcedure;
begin
  Result := TPasProcedure(FDescs.Get[I]);
end;

function TVetNested.IndexOf(const D: TPasElement): Integer;
begin
  Result := FDescs.Get.IndexOf(D);
end;

function TVetNested.Writes(const I: Integer): TFPList;
begin
  Result := TFPList(FWrites.Get[I]);
end;

function TVetNested.Refs(const I: Integer): TFPList;
begin
  Result := TFPList(FRefs.Get[I]);
end;

end.
