{ SPDX-License-Identifier: MIT }
{ bpvet rule S28 (safe/SPEC.md §25.3): a view of a String (TStrView, a part of a String without a reference to it) does
  not outlive its String, and the String is not written while views of it live. It runs in the typed mode on a module
  that resolved (bpvettyped.pas). The design: the comment "a string view without a reference (TStrView) and the borrow
  rule S28" of unxed/bp#108.

  A view is a value of a view type: TStrView, TViewFields, a record or an array that holds one, or a specialization of
  a generic record (TMap, TGrowArray) with a view type among its type arguments. The root of a view is the String it is
  a part of:
    StrView(X), FieldViews(X) and a call of a routine whose result is a view of its String parameter P have the root
      X (the argument for P). X must be a local variable or a value or const parameter of type String of the routine:
      a field, a global (or threadvar), a function result, a temporary expression or a var/out parameter is an error.
      A string literal or a constant is never written, so it is allowed.
    V.Sub(...), for W in FieldViews(S), F.Next(W), a field or an element of a view, and a map that gets a view as a key
      or a value (M.Ref(W, 0), M.Put(W, X), M[W] := X) keep the root.
  The rules:
    escape  a view lives only in the locals of the routine (and in value parameters, which are locals): storing one into
            a field, a global, the result (outside its root), a var/out parameter, a local of the enclosing routine, a
            place reached through a pointer or an object is an error; so is passing one to Send of a channel, to the
            constructor of a task, to Go, or to a TOwned, TShared, TArena or TRegion; and a nested routine that reads a
            view of the routine is not used as a procedure value. A field of a class and a global of a view type are
            errors where they are declared (a task and a region object are classes). A view goes down as a const or
            value parameter: the callee is checked by the same rule.
    result  the parameter that the result of a function is a view of: the one named by // root: P on its header line
            (as S17 does for regions); without the mark, its only String or view parameter (elided, as lifetimes in
            Rust); with several, what its body returns, inferred over the module, except that an exported routine
            writes the mark (a contract for other units). The result may be rooted there only, and the calls root it
            in the argument. A method of a view type returns views of Self without a mark.
    write   a write of S is an error when a variable that may hold a view of S at that point is read after it, or when a
            loop for ... in over a view of S is running (its enumerator reads S in the next round): S := ...,
            S[I] := ..., SetLength, UniqueString, Insert, Delete, SetString, Str, Read, ReadLn, a var/out argument, @S,
            a for-in loop over S, a call of a nested routine that writes S (through the nested routines it calls,
            bpvetnested.pas), and a call of a procedure value once such a routine is used as one. Two walks over the
            statements: liveness backward (a plain assignment V := ... ends the life of V; if, case, loops to a fixed
            point, a try block may go to its handler from any statement; Exit, Break and Continue fall through, which
            keeps more alive), and forward the views each variable may hold (a plain assignment replaces them, a
            branch joins, a loop is walked twice). A write after the last use of every view of S is fine.
  A finding with // UNSAFE: <why> on its line (or in a comment block right above) is not reported; a // UNSAFE-UNIT:
  module is not checked. }
unit BpvetS28;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, PasTree, PasResolveEval, PasResolver, BpvetCore, BpvetS17, BpvetNested, Safe;

procedure VetCheckS28(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);

implementation

type
  TRoots = Int64;  // a set of roots: bit I is FRoots[I]; bit 0 is Self of a method of a view type
  TLinesBox = specialize TOwned<TStringList>;
  TListBox = specialize TOwned<TFPList>;
  // UNSAFE: the key is the identity of an element of the tree, which is never dereferenced through it
  TCache = specialize TMap<System.Pointer, Byte>;  // a type or a declaration: 1 not a view, 2 a view, 3 being computed

  TRootInfo = record
    Decl: TPasElement;   // the String local or parameter, a view parameter, or nil (Self, the enclosing routine)
    Name: String;
  end;

  TVarInfo = record
    Decl: TPasElement;   // a local or a parameter of a view type
    Roots: TRoots;
  end;

  TRootsArray = array of TRoots;

  TS28 = class
  private
    FSrc: TVetSource;
    FResolver: TPasResolver;  // borrow: the resolver of the checked module, alive during the check
    FModule: TPasModule;      // borrow: the checked module, alive during the check
    FReport: TVetReport;
    FSeen: TLinesBox;
    FLines: TLinesBox;        // name=file for the sources of other files read for // root: and // UNSAFE:
    FTypes: TCache;
    FDecls: TCache;
    FFlagged: TListBox;       // the fields and globals of a view type reported where they are declared
    FNodes: TListBox;         // what Collect gathers
    FBody: TListBox;          // the elements of the body being checked
    FProc: TPasProcedure;     // borrow: the routine being checked, nil for the main block of a program
    FDecl: TPasProcedure;     // borrow: its declaration in the interface or a forward one, else nil
    FSelfType: TPasType;      // borrow: the view type whose method is checked, else nil
    FRoots: array of TRootInfo;
    FVars: array of TVarInfo;
    FNest: TVetNested;        // borrow: the nested routines of FProc, during CheckWrites; nil without them
    FNestWrites: array of TRoots;  // the roots each nested routine writes
    FNestUses: array of Int64;     // the variables (VarBit) each nested routine reads
    FEvNodes: TListBox;       // the writes of the roots (and the calls that write them)
    FEvHows: TLinesBox;       // for each: "how<tab>root"
    FLiveAt: TListBox;        // statements, with FLiveSets: the variables live right after each
    FLiveSets: array of Int64;
    FExc: Int64;              // the variables live in the handler of the try block being walked
    FExtra: TRoots;           // the roots of the views held by the running loops for ... in
    FQuietLoops: Integer;     // the first round of a loop reports nothing
    FStrong: Boolean;         // a plain assignment replaces the roots of the variable
    FStrongOK: Boolean;       // the forward walk of CheckWrites, where FStrong applies
    FStart: TRootsArray;      // the roots of the variables at the start of the routine
    FInferred: TLinesBox;     // key of a routine=",a,b,": the parameters its result is a view of, from its body
    FInfer: Boolean;          // the inference passes: no findings, FInferred grows
    FInferChanged: Boolean;
    FResultOK: TRoots;        // the roots the result may have (// root:)
    FOuter: Integer;          // the root of the views of the enclosing routine, -1 until one is read
    FFinal: Boolean;          // the last pass: findings are reported
    FChanged: Boolean;
    procedure Collect(El: TPasElement; Arg: Pointer);
    function Ref(const E: TPasElement): TPasElement;
    function TypeOf(const E: TPasElement): TPasType;
    function Resolve(const T: TPasElement): TPasType;
    function LineOf(const FileName: String; const Row: Integer): String;
    function Marked(const El: TPasElement): Boolean;
    procedure Add(const El: TPasElement; const Msg: String);
    function IsViewType(const T: TPasType): Boolean;
    function IsViewOrPtr(const T: TPasType): Boolean;
    function DeclType(const D: TPasElement): TPasType;
    function IsViewDecl(const D: TPasElement): Boolean;
    function IsStringDecl(const D: TPasElement): Boolean;
    function IsLocal(const D: TPasElement): Boolean;
    function IsOwnParam(const D: TPasElement): Boolean;
    function IsOuter(const D: TPasElement): Boolean;
    function Callee(const P: TPasExpr; out Recv: TPasExpr): TPasElement;
    function IsMaker(const C: TPasElement): Boolean;
    function IsViewMethod(const C: TPasElement): Boolean;
    function MarkOf(const P: TPasProcedure): String;
    function Key(const P: TPasProcedure): String;
    function Candidates(const P: TPasProcedure; out Only: String): Integer;
    function Exported(const P: TPasProcedure): Boolean;
    function EffectiveMark(const P: TPasProcedure): String;
    function RootIndex(const Decl: TPasElement): Integer;
    function AddRoot(const ADecl: TPasElement; const AName: String): Integer;
    function VarIndex(const D: TPasElement): Integer;
    function RootNames(const R: TRoots): String;
    function RootBits(const X: TPasExpr): TRoots;
    function Describe(const X: TPasExpr): String;
    procedure CheckRoot(const X: TPasExpr; const Call: TPasExpr; const Maker: String);
    function CallRoots(const C: TPasProcedure; const Recv: TPasExpr; const Args: array of TPasExpr): TRoots;
    function Eval(const E: TPasExpr): TRoots;
    procedure Escape(const L: TPasExpr; const What: String);
    procedure CheckResult(const V: TRoots; const Where: TPasElement);
    procedure Store(const L: TPasExpr; const V: TRoots);
    procedure CallEffects(const P: TParamsExpr);
    procedure Step(const N: TPasElement);
    procedure Pass;
    procedure NodesOf(const El: TPasElement; const L: TFPList);
    procedure CollectWrites;
    function UsesOf(const L: TFPList; const Skip: TPasElement): Int64;
    function ExprUses(const E: TPasElement): Int64;
    procedure Record_(const El: TPasElement; const Live: Int64);
    function Live(const El: TPasElement; const Out: Int64): Int64;
    procedure Steps(const L: TFPList);
    procedure ExprSteps(const E: TPasElement);
    procedure CheckAt(const El: TPasElement);
    procedure SaveRoots(out R: TRootsArray);
    procedure JoinRoots(const R: TRootsArray);
    procedure LoadRoots(const R: TRootsArray);
    procedure Fwd(const El: TPasElement);
    procedure CheckWrites(const Block: TPasImplBlock; const Start: TRootsArray);
    procedure CheckCapture;
    procedure CheckBody(const Block: TPasImplBlock);
  public
    constructor Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
    procedure CheckRoutine(const P: TPasProcedure);
    procedure CheckMain(const Block: TPasImplBlock);
    procedure CheckDecls(const Decls: TPasDeclarations; const Top: Boolean);
    function NeedsInference(const Decls: TPasDeclarations): Boolean;
    procedure Flush(var Report: TVetReport);
  end;

  TS28Box = specialize TOwned<TS28>;

const
  MaxRoots = 63;
  SpecRef = ' (safe/SPEC.md section 25.3)';

function Bit(const I: Integer): TRoots;
begin
  Result := TRoots(1) shl I;
end;

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

{ ---------- TS28 ---------- }

constructor TS28.Create(const ASrc: TVetSource; const AResolver: TPasResolver; const AModule: TPasModule);
begin
  inherited Create;
  FSrc := ASrc;
  // borrow: the resolver outlives the check (VetResolve)
  FResolver := AResolver;
  // borrow: the module outlives the check (VetResolve)
  FModule := AModule;
  FSeen := TLinesBox.Own(TStringList.Create);
  FSeen.Get.Sorted := True;
  FLines := TLinesBox.Own(TStringList.Create);
  FLines.Get.OwnsObjects := True;
  FFlagged := TListBox.Own(TFPList.Create);
  FNodes := TListBox.Own(TFPList.Create);
  FBody := TListBox.Own(TFPList.Create);
  FEvNodes := TListBox.Own(TFPList.Create);
  FEvHows := TLinesBox.Own(TStringList.Create);
  FLiveAt := TListBox.Own(TFPList.Create);
  FInferred := TLinesBox.Own(TStringList.Create);
end;

// UNSAFE: the signature of TPasElement.ForEachCall (TPasElementWalkProc), Arg is not used
procedure TS28.Collect(El: TPasElement; Arg: Pointer);
begin
  FNodes.Get.Add(El);
end;

{ What E names; a parameter of the declaration of the routine being checked is the same parameter of its body. }
function TS28.Ref(const E: TPasElement): TPasElement;
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

function TS28.TypeOf(const E: TPasElement): TPasType;
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

{ The type T denotes, through aliases and specializations; nil when it does not resolve. }
function TS28.Resolve(const T: TPasElement): TPasType;
begin
  Result := TypeOf(T);
end;

function TS28.LineOf(const FileName: String; const Row: Integer): String;
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
function TS28.Marked(const El: TPasElement): Boolean;
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

procedure TS28.Add(const El: TPasElement; const Msg: String);
var
  Row: Integer;
  Seen, FileName: String;
begin
  if not FFinal or FInfer or (El = nil) then
    Exit;
  Row := El.SourceLinenumber;
  if Marked(El) then
    Exit;
  Seen := Format('%s %.6d %s', [El.SourceFilename, Row, Msg]);
  if FSeen.Get.IndexOf(Seen) >= 0 then
    Exit;
  FSeen.Get.Add(Seen);
  // an element of an include file is reported in that file
  FileName := FSrc.FileName;
  if (El.SourceFilename <> '') and not SameFileName(ExpandFileName(El.SourceFilename), ExpandFileName(FileName)) then
    FileName := El.SourceFilename;
  VetAdd(FReport, FileName, Row, VetWordColumn(LineOf(El.SourceFilename, Row), NameOf(El)), vsError, 'S28', Msg);
end;

{ ---------- view types ---------- }

{ T is a view type: TStrView, TViewFields, a record or an array that holds one, or a specialization with a view type
  argument. A class, a pointer and a String are not: what they refer to is elsewhere. }
function TS28.IsViewType(const T: TPasType): Boolean;
var
  C: Byte;
  I: Integer;
  M: TPasElement;
  Item: TPRSpecializedItem;
begin
  Result := False;
  if T = nil then
    Exit;
  C := FTypes.Get(T, 0);
  if C <> 0 then
    Exit(C = 2);
  FTypes.Put(T, 3);
  if T is TPasRecordType then
  begin
    if SameText(T.Name, 'TStrView') or SameText(T.Name, 'TViewFields') then
      Result := True
    else
    begin
      if (T.CustomData is TPasGenericScope) and (TPasGenericScope(T.CustomData).SpecializedFromItem <> nil) then
      begin
        Item := TPasGenericScope(T.CustomData).SpecializedFromItem;
        for I := 0 to High(Item.Params) do
          if IsViewType(Resolve(Item.Params[I])) then
            Result := True;
      end;
      I := 0;
      while not Result and (I < TPasRecordType(T).Members.Count) do
      begin
        M := TPasElement(TPasRecordType(T).Members[I]);
        if (M.ClassType = TPasVariable) and IsViewType(Resolve(TPasVariable(M).VarType)) then
          Result := True;
        Inc(I);
      end;
    end;
  end
  else if T is TPasArrayType then
    Result := IsViewType(Resolve(TPasArrayType(T).ElType));
  if Result then
    FTypes.Put(T, 2)
  else
    FTypes.Put(T, 1);
end;

{ A view type, or a pointer to one (the result of Ref of a TMap of views). }
function TS28.IsViewOrPtr(const T: TPasType): Boolean;
begin
  Result := IsViewType(T) or ((T is TPasPointerType) and IsViewType(Resolve(TPasPointerType(T).DestType)));
end;

{ The type of the variable, the parameter, the result or the function result D; nil for anything else. }
function TS28.DeclType(const D: TPasElement): TPasType;
begin
  Result := nil;
  if D is TPasProcedure then
  begin
    if TPasProcedure(D).ProcType is TPasFunctionType then
      Result := Resolve(TPasFunctionType(TPasProcedure(D).ProcType).ResultEl.ResultType);
  end
  else if D is TPasArgument then
    Result := Resolve(TPasArgument(D).ArgType)
  else if D is TPasResultElement then
    Result := Resolve(TPasResultElement(D).ResultType)
  else if (D is TPasVariable) and (TPasVariable(D).VarType <> nil) then
    Result := Resolve(TPasVariable(D).VarType);
end;

function TS28.IsViewDecl(const D: TPasElement): Boolean;
var
  C: Byte;
begin
  if D = nil then
    Exit(False);
  C := FDecls.Get(D, 0);
  if C <> 0 then
    Exit(C = 2);
  Result := IsViewOrPtr(DeclType(D));
  if Result then
    FDecls.Put(D, 2)
  else
    FDecls.Put(D, 1);
end;

{ D is of type String (AnsiString): a view of another string type would be a view of a temporary copy. }
function TS28.IsStringDecl(const D: TPasElement): Boolean;
var
  R: TPasResolverResult;
begin
  Result := False;
  try
    FResolver.ComputeElement(D, R, []);
    Result := R.BaseType in [btString, btAnsiString, btRawByteString];
  except
    on Exception do
      Result := False;
  end;
end;

{ D is a variable declared by the routine being checked. }
function TS28.IsLocal(const D: TPasElement): Boolean;
begin
  Result := (D is TPasVariable) and not (D is TPasConst) and not (D is TPasProperty) and (FProc <> nil)
    and (FProc.Body <> nil) and (D.Parent = FProc.Body);
end;

function TS28.IsOwnParam(const D: TPasElement): Boolean;
begin
  Result := (D is TPasArgument) and (FProc <> nil) and (D.Parent = FProc.ProcType);
end;

{ D is Self of a method (the resolver gives it as a parameter of the routine). }
function IsSelfArg(const D: TPasElement): Boolean;
begin
  Result := (D is TPasArgument) and (D.Parent is TPasProcedure) and SameText(D.Name, 'Self');
end;

{ D is a variable or a parameter of a routine that encloses the one being checked. }
function TS28.IsOuter(const D: TPasElement): Boolean;
begin
  Result := not IsSelfArg(D) and (((D is TPasVariable) and (D.Parent is TProcedureBody)) or (D is TPasArgument))
    and not IsLocal(D)
    and not IsOwnParam(D) and not ((D is TPasArgument) and (FDecl <> nil) and (D.Parent = FDecl.ProcType));
end;

{ The routine (or type, for a cast) that the call P calls, and its receiver (nil without one). }
function TS28.Callee(const P: TPasExpr; out Recv: TPasExpr): TPasElement;
var
  V: TPasExpr;
begin
  Recv := nil;
  V := P;
  if V is TParamsExpr then
    V := TParamsExpr(V).Value;
  if (V is TBinaryExpr) and (TBinaryExpr(V).OpCode = eopSubIdent) then
  begin
    Result := Ref(TBinaryExpr(V).right);
    Recv := TBinaryExpr(V).left;
    if (Ref(Recv) is TPasType) or (Ref(Recv) is TPasModule) then
      Recv := nil;
  end
  else
    Result := Ref(V);
end;

{ C makes a view of its String argument: StrView or FieldViews. }
function TS28.IsMaker(const C: TPasElement): Boolean;
begin
  Result := (C is TPasProcedure) and not (C.Parent is TPasMembersType)
    and (SameText(C.Name, 'StrView') or SameText(C.Name, 'FieldViews')) and IsViewDecl(C);
end;

{ C is a method of a view type: its result is a view of the receiver. }
function TS28.IsViewMethod(const C: TPasElement): Boolean;
begin
  Result := (C is TPasProcedure) and (C.Parent is TPasRecordType) and IsViewType(TPasType(C.Parent));
end;

{ The // root: names of P, on its header line or on that of its declaration. }
function TS28.MarkOf(const P: TPasProcedure): String;
begin
  Result := VetRootMark(LineOf(P.SourceFilename, P.SourceLinenumber));
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    Result := Result + VetRootMark(LineOf(TPasProcedureScope(P.CustomData).DeclarationProc.SourceFilename,
      TPasProcedureScope(P.CustomData).DeclarationProc.SourceLinenumber));
end;

{ A routine and its declaration (in the interface, or a forward one) share one entry. }
function TS28.Key(const P: TPasProcedure): String;
var
  D: TPasProcedure;
begin
  D := P;
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    D := TPasProcedureScope(P.CustomData).DeclarationProc;
  Result := IntToHex(PtrUInt(D), 16);
end;

{ The parameters of P that a view it returns may be a part of: a String (value or const) or a view. Only: the name
  of the first one. }
function TS28.Candidates(const P: TPasProcedure; out Only: String): Integer;
var
  I: Integer;
  A: TPasArgument;
begin
  Result := 0;
  Only := '';
  for I := 0 to P.ProcType.Args.Count - 1 do
  begin
    A := TPasArgument(P.ProcType.Args[I]);
    if (A.Access in [argDefault, argConst, argConstRef]) and ((A.ArgType <> nil) and IsViewDecl(A)
      or IsStringDecl(A)) then
    begin
      Inc(Result);
      if Only = '' then
        Only := A.Name;
    end;
  end;
end;

{ P is declared in the interface of its unit (a routine, or a method of a type declared there). }
function TS28.Exported(const P: TPasProcedure): Boolean;
var
  D: TPasElement;
begin
  D := P;
  if (P.CustomData is TPasProcedureScope) and (TPasProcedureScope(P.CustomData).DeclarationProc <> nil) then
    D := TPasProcedureScope(P.CustomData).DeclarationProc;
  while (D <> nil) and not (D is TPasSection) do
    D := D.Parent;
  Result := (D <> nil) and (D is TInterfaceSection);
end;

{ The parameters the result of P is a view of: its // root: mark; else its only String or view parameter (the mark is
  elided); else, for a routine of this module, what its body returns (inferred). }
function TS28.EffectiveMark(const P: TPasProcedure): String;
var
  Only: String;
begin
  Result := MarkOf(P);
  if Result <> '' then
    Exit;
  if Candidates(P, Only) = 1 then
    Exit(',' + LowerCase(Only) + ',');
  Result := FInferred.Get.Values[Key(P)];
end;

function TS28.RootIndex(const Decl: TPasElement): Integer;
var
  I: Integer;
begin
  for I := 1 to High(FRoots) do
    if FRoots[I].Decl = Decl then
      Exit(I);
  Result := -1;
end;

function TS28.AddRoot(const ADecl: TPasElement; const AName: String): Integer;
begin
  Result := Length(FRoots);
  if Result > MaxRoots then
    Exit(MaxRoots); // too many roots: the extra ones share the last bit
  SetLength(FRoots, Result + 1);
  FRoots[Result].Decl := ADecl;
  FRoots[Result].Name := AName;
end;

function TS28.VarIndex(const D: TPasElement): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FVars) do
    if FVars[I].Decl = D then
      Exit(I);
  Result := -1;
end;

function TS28.RootNames(const R: TRoots): String;
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

{ The root of a view of X: a String local or value or const parameter of the routine; 0 for anything else. }
function TS28.RootBits(const X: TPasExpr): TRoots;
var
  D: TPasElement;
  K: Integer;
begin
  Result := 0;
  if not ((X is TPrimitiveExpr) and (TPrimitiveExpr(X).Kind = pekIdent)) then
    Exit;
  D := Ref(X);
  if not (IsLocal(D) or (IsOwnParam(D) and (TPasArgument(D).Access in [argDefault, argConst, argConstRef])))
    or not IsStringDecl(D) then
    Exit;
  K := RootIndex(D);
  if K < 0 then
    K := AddRoot(D, D.Name);
  Result := Bit(K);
end;

{ Why X cannot be the String of a view; '' when it can. }
function TS28.Describe(const X: TPasExpr): String;
var
  D: TPasElement;
begin
  Result := '';
  if (X is TPrimitiveExpr) and (TPrimitiveExpr(X).Kind = pekString) then
    Exit; // a literal is never written
  if not ((X is TPrimitiveExpr) and (TPrimitiveExpr(X).Kind = pekIdent)) then
  begin
    if (X is TBinaryExpr) and (TBinaryExpr(X).OpCode = eopSubIdent) and (Ref(TBinaryExpr(X).right) is TPasVariable)
      and not (Ref(TBinaryExpr(X).right) is TPasProperty) then
      Exit('the field ' + NameOf(X));
    Exit('a temporary (an expression, a call or a property): it is freed at the end of the statement');
  end;
  D := Ref(X);
  if RootBits(X) <> 0 then
    Exit;
  if D is TPasConst then
    Exit; // a constant is never written
  if (D is TPasArgument) and IsOwnParam(D) and (TPasArgument(D).Access in [argVar, argOut]) then
    Result := Format('the var/out parameter %s: the caller may change it', [D.Name])
  else if (IsOwnParam(D) or IsLocal(D)) then
    Result := Format('%s, which is not a String: the view would be of a temporary copy', [D.Name])
  else if (D is TPasResultElement) or (D is TPasProcedure) then
    Result := 'the result of a function (a temporary)'
  else if (D is TPasVariable) and (D.Parent is TPasMembersType) then
    Result := 'the field ' + D.Name
  else if IsOuter(D) then
    Result := Format('%s of the enclosing routine', [D.Name])
  else if D is TPasVariable then
    Result := Format('the global (or threadvar) %s', [D.Name])
  else
    Result := 'not a variable';
end;

{ The view made by Call (StrView, FieldViews, a // root: routine) of the String X. }
procedure TS28.CheckRoot(const X: TPasExpr; const Call: TPasExpr; const Maker: String);
var
  Why: String;
  R: TRoots;
begin
  R := RootBits(X);
  if R <> 0 then
    Exit;
  Why := Describe(X);
  if Why <> '' then
    Add(Call, Format('%s(%s): the String of a view is %s; a view holds no reference, so its String must be a local '
      + 'variable or a const parameter of this routine: copy it into a local first' + SpecRef,
      [Maker, NameOf(X), Why]));
end;

{ The roots of the result of a call of C (on Recv, if a method) with Args. }
function TS28.CallRoots(const C: TPasProcedure; const Recv: TPasExpr; const Args: array of TPasExpr): TRoots;
var
  Mark: String;
  I: Integer;
  Formal: TPasArgument;
begin
  Result := 0;
  if not IsViewDecl(C) then
    Exit;
  if IsMaker(C) then
  begin
    if Length(Args) > 0 then
      Result := RootBits(Args[0]);
    Exit;
  end;
  Mark := EffectiveMark(C);
  if IsViewMethod(C) then
  begin
    if Recv <> nil then
      Result := Eval(Recv)
    else if (FSelfType <> nil) and (C.Parent = FSelfType) then
      Result := Bit(0);
  end
  else if VetInMark(Mark, 'Self') and (Recv <> nil) then
    Result := Eval(Recv);
  for I := 0 to C.ProcType.Args.Count - 1 do
  begin
    if I > High(Args) then
      Break;
    Formal := TPasArgument(C.ProcType.Args[I]);
    if not VetInMark(Mark, Formal.Name) then
      Continue;
    if IsViewDecl(Formal) then
      Result := Result or Eval(Args[I])
    else
      Result := Result or RootBits(Args[I]);
  end;
end;

function TS28.Eval(const E: TPasExpr): TRoots;
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
      Result := CallRoots(TPasProcedure(D), nil, [])
    else
    begin
      K := VarIndex(D);
      if K >= 0 then
        Result := FVars[K].Roots
      else if IsSelfArg(D) then
      begin
        if FSelfType <> nil then
          Result := Bit(0);
      end
      else if (FSelfType <> nil) and (D is TPasVariable) and (D.Parent = FSelfType) then
        Result := Bit(0)
      else if IsOuter(D) and IsViewDecl(D) then
      begin
        if FOuter < 0 then
          FOuter := AddRoot(nil, 'a view of the enclosing routine');
        Result := Bit(FOuter);
      end;
    end;
  end
  else if E is TSelfExpr then
  begin
    if FSelfType <> nil then
      Result := Bit(0);
  end
  else if (E is TBinaryExpr) and (TBinaryExpr(E).OpCode = eopSubIdent) then
  begin
    B := TBinaryExpr(E);
    D := Ref(B.right);
    if (D is TPasProcedure) and (B.right is TPrimitiveExpr) then
    begin
      if (Ref(B.left) is TPasType) or (Ref(B.left) is TPasModule) then
        Result := CallRoots(TPasProcedure(D), nil, [])
      else
        Result := CallRoots(TPasProcedure(D), B.left, []);
    end
    else if B.right is TParamsExpr then
      Result := Eval(B.right) // A.B(...) is a TParamsExpr with the value A.B
    else
      Result := Eval(B.left); // a field: the roots of its record
  end
  else if E is TParamsExpr then
  begin
    P := TParamsExpr(E);
    if P.Kind = pekArrayParams then
      Result := Eval(P.Value) // A[I], M[K]: the roots of A, M
    else if P.Kind = pekFuncParams then
    begin
      D := Callee(P, Recv);
      SetLength(Args, Length(P.Params));
      for I := 0 to High(P.Params) do
        Args[I] := P.Params[I];
      if D is TPasType then
      begin
        if Length(Args) = 1 then
          Result := Eval(Args[0]); // a type cast keeps the roots
      end
      else if D is TPasProcedure then
        Result := CallRoots(TPasProcedure(D), Recv, Args);
    end;
  end
  else if (E is TUnaryExpr) and (TUnaryExpr(E).OpCode = eopDeref) then
    Result := Eval(TUnaryExpr(E).Operand);
  if (Result <> 0) and not IsViewOrPtr(TypeOf(E)) then
    Result := 0;
end;

procedure TS28.Escape(const L: TPasExpr; const What: String);
begin
  Add(L, Format('a view (a TStrView, or a value that holds one) is stored into %s, which may outlive its String: a '
    + 'view holds no reference, so it lives only in locals of the routine and goes down as a const parameter; keep a '
    + 'copy (W.ToString, a TStrSlice) instead' + SpecRef, [What]));
end;

{ Result := (a view with the roots V) }
procedure TS28.CheckResult(const V: TRoots; const Where: TPasElement);
var
  Bad: TRoots;
  I: Integer;
begin
  if (FProc = nil) or not IsViewDecl(FProc) then
    Exit;
  if FInfer then
  begin
    // the parameters among the roots of the result grow the inferred mark of a routine without a written one
    if (MarkOf(FProc) = '') and (FSelfType = nil) then
      for I := 1 to High(FRoots) do
        if (V and Bit(I) <> 0) and (FRoots[I].Decl is TPasArgument) and IsOwnParam(FRoots[I].Decl)
          and not VetInMark(FInferred.Get.Values[Key(FProc)], FRoots[I].Name) then
        begin
          if FInferred.Get.Values[Key(FProc)] = '' then
            FInferred.Get.Values[Key(FProc)] := ',';
          FInferred.Get.Values[Key(FProc)] := FInferred.Get.Values[Key(FProc)] + LowerCase(FRoots[I].Name) + ',';
          FInferChanged := True;
        end;
    Exit;
  end;
  if FResultOK = 0 then
    Exit; // the header has no // root: mark, which is reported once on the header
  Bad := V and not FResultOK;
  if Bad <> 0 then
    Add(Where, Format('the result of %s gets a view of %s, which is not a parameter its result may be a view of '
      + '(// root:, or the only String parameter): the view would outlive its String; return a view of that '
      + 'parameter, or a copy (W.ToString)' + SpecRef, [FProc.Name, RootNames(Bad)]));
end;

{ L := (a view with the roots V) }
procedure TS28.Store(const L: TPasExpr; const V: TRoots);
var
  D: TPasElement;
  K, I: Integer;
  T: TPasType;
  Base, Recv: TPasExpr;
  Idx: TRoots;
begin
  if L is TPrimitiveExpr then
  begin
    D := Ref(L);
    if IsSelfArg(D) then
    begin
      if FSelfType = nil then
        Escape(L, 'Self');
      Exit;
    end;
    if (D is TPasArgument) and IsOwnParam(D) and (TPasArgument(D).Access in [argVar, argOut]) then
    begin
      Escape(L, 'the var/out parameter ' + D.Name);
      Exit;
    end;
    K := VarIndex(D);
    if K >= 0 then
    begin
      if FStrong then
        FVars[K].Roots := V
      else if FVars[K].Roots or V <> FVars[K].Roots then
      begin
        FVars[K].Roots := FVars[K].Roots or V;
        FChanged := True;
      end;
    end
    else if (D is TPasResultElement) or ((FProc <> nil) and (D = FProc)) or ((FDecl <> nil) and (D = FDecl)) then
      CheckResult(V, L)
    else if (FSelfType <> nil) and (D is TPasVariable) and (D.Parent = FSelfType) then
      // a field of Self in a method of a view type: Self holds the view
    else if FFlagged.Get.IndexOf(D) >= 0 then
      // the field or the global is reported where it is declared
    else if (D is TPasVariable) and (D.Parent is TPasMembersType) then
      Escape(L, 'the field ' + D.Name)
    else if IsOuter(D) then
      Escape(L, Format('%s of the enclosing routine', [D.Name]))
    else if (D is TPasVariable) and not (D is TPasConst) then
      Escape(L, Format('the global (or threadvar) %s', [D.Name]));
    Exit;
  end;
  if L is TSelfExpr then
  begin
    if FSelfType = nil then
      Escape(L, 'Self');
    Exit;
  end;
  if (L is TBinaryExpr) and (TBinaryExpr(L).OpCode = eopSubIdent) then
  begin
    Base := TBinaryExpr(L).left;
    T := TypeOf(Base);
    D := Ref(TBinaryExpr(L).right);
    if (T is TPasRecordType) or (T is TPasArrayType) then
      Store(Base, V) // a field of a record: the record holds the view
    else if FFlagged.Get.IndexOf(D) < 0 then
      Escape(L, 'the field ' + NameOf(L) + ' of an object');
    Exit;
  end;
  if (L is TParamsExpr) and (TParamsExpr(L).Kind = pekArrayParams) then
  begin
    Base := TParamsExpr(L).Value;
    T := TypeOf(Base);
    Idx := 0;
    for I := 0 to High(TParamsExpr(L).Params) do
      Idx := Idx or Eval(TParamsExpr(L).Params[I]);
    if (T is TPasRecordType) or (T is TPasArrayType) then
      Store(Base, V or Idx)
    else if (T is TPasClassType) or (T is TPasPointerType) then
      Escape(L, 'an element of an object');
    Exit;
  end;
  if (L is TUnaryExpr) and (TUnaryExpr(L).OpCode = eopDeref) then
  begin
    Base := TUnaryExpr(L).Operand;
    if (Base is TParamsExpr) and (Callee(Base, Recv) is TPasProcedure) and (Recv <> nil) then
      Store(Recv, V) // M.Ref(K, D)^ := W: the map M holds the view
    else
      Escape(TUnaryExpr(L).Operand, 'a place reached through a pointer');
  end;
end;

{ A call: views go into its receiver and its var/out arguments, a view made of a String, a view given to an owner. }
procedure TS28.CallEffects(const P: TParamsExpr);
var
  C: TPasElement;
  Recv: TPasExpr;
  I: Integer;
  Formal: TPasArgument;
  ViewArgs, In_: TRoots;
  Mark, N, Owner: String;
  Sink: Boolean;
  X: TPasType;
begin
  if P.Kind <> pekFuncParams then
    Exit;
  C := Callee(P, Recv);
  if C = nil then
    Exit;
  if (C.CustomData is TResElDataBuiltInProc) and (TResElDataBuiltInProc(C.CustomData).BuiltIn = bfExit) then
  begin
    if (Length(P.Params) = 1) and (FProc <> nil) and IsViewDecl(FProc) then
      CheckResult(Eval(P.Params[0]), P.Params[0]);
    Exit;
  end;
  if not (C is TPasProcedure) then
    Exit;
  N := LowerCase(C.Name);
  // the String of a view
  if IsMaker(C) then
  begin
    if Length(P.Params) > 0 then
      CheckRoot(P.Params[0], P, C.Name);
  end
  else if IsViewDecl(C) and not IsViewMethod(C) then
  begin
    Mark := EffectiveMark(TPasProcedure(C));
    for I := 0 to Min(TPasProcedure(C).ProcType.Args.Count, Length(P.Params)) - 1 do
    begin
      Formal := TPasArgument(TPasProcedure(C).ProcType.Args[I]);
      if VetInMark(Mark, Formal.Name) and not IsViewDecl(Formal) then
        CheckRoot(P.Params[I], P, C.Name);
    end;
    if (Mark = '') and (C.GetModule <> FModule) then
      Add(P, Format('%s returns a view, and its header has no // root: mark naming the String it is a view of: the '
        + 'root of the result is not known' + SpecRef, [C.Name]));
  end;
  // the roots of the views among the arguments
  ViewArgs := 0;
  Sink := False;
  Owner := '';
  if C.Parent is TPasType then
    Owner := C.Parent.Name;
  if ((N = 'send') and (SameText(Copy(Owner, 1, 5), 'TChan') or SameText(Copy(Owner, 1, 9), 'TSafeChan')))
    or SameText(Copy(Owner, 1, 6), 'TOwned') or SameText(Copy(Owner, 1, 7), 'TShared')
    or SameText(Copy(Owner, 1, 6), 'TArena') or SameText(Owner, 'TRegion')
    or ((N = 'go') and not (C.Parent is TPasMembersType)) then
    Sink := True
  else if (C is TPasConstructor) and (C.Parent is TPasClassType) then
  begin
    X := TPasType(C.Parent);
    while X is TPasClassType do
    begin
      if SameText(X.Name, 'TTask') then
      begin
        Sink := True;
        Break;
      end;
      X := Resolve(TPasClassType(X).AncestorType);
    end;
  end;
  for I := 0 to High(P.Params) do
  begin
    if I < TPasProcedure(C).ProcType.Args.Count then
      Formal := TPasArgument(TPasProcedure(C).ProcType.Args[I])
    else
      Formal := nil;
    if (Formal <> nil) and (Formal.Access in [argVar, argOut]) then
      Continue;
    if ((Formal <> nil) and (Formal.ArgType <> nil) and IsViewDecl(Formal))
      or (((Formal = nil) or (Formal.ArgType = nil) or Sink) and IsViewOrPtr(TypeOf(P.Params[I]))) then
    begin
      ViewArgs := ViewArgs or Eval(P.Params[I]);
      if Sink then
        Add(P.Params[I], Format('a view (a TStrView, or a value that holds one) is passed to %s, which keeps it '
          + 'beyond this routine (another goroutine, a task, an owner or a region): a view holds no reference to its '
          + 'String; pass a copy (W.ToString, a TStrSlice)' + SpecRef, [NameOf(P.Value)]));
    end;
  end;
  // a map (a value of a view type) that gets a view holds it
  In_ := ViewArgs;
  if IsViewMethod(C) then
  begin
    if (Recv <> nil) and (ViewArgs <> 0) then
      Store(Recv, ViewArgs);
    if Recv <> nil then
      In_ := In_ or Eval(Recv)
    else if (FSelfType <> nil) and (C.Parent = FSelfType) then
      In_ := In_ or Bit(0);
  end;
  // var and out arguments of a view type get the views of the call
  for I := 0 to Min(TPasProcedure(C).ProcType.Args.Count, Length(P.Params)) - 1 do
  begin
    Formal := TPasArgument(TPasProcedure(C).ProcType.Args[I]);
    if not (Formal.Access in [argVar, argOut]) then
      Continue;
    if ((Formal.ArgType <> nil) and IsViewDecl(Formal))
      or ((Formal.ArgType = nil) and IsViewOrPtr(TypeOf(P.Params[I]))) then
      Store(P.Params[I], In_);
  end;
end;

{ The effects of the element N: an assignment, a loop for ... in, a call. }
procedure TS28.Step(const N: TPasElement);
var
  J: Integer;
  A: TPasImplAssign;
  L: TPasImplForLoop;
  Idx: TRoots;
  Base: TPasExpr;
begin
    if N is TPasImplAssign then
    begin
      A := TPasImplAssign(N);
      if IsViewOrPtr(TypeOf(A.left)) then
      begin
        FStrong := FStrongOK and (A.Kind = akDefault) and (A.left is TPrimitiveExpr);
        Store(A.left, Eval(A.right));
        FStrong := False;
      end
      else if (A.left is TParamsExpr) and (TParamsExpr(A.left).Kind = pekArrayParams) then
      begin
        // M[K] := X with a view K: the map holds the key
        Base := TParamsExpr(A.left).Value;
        if IsViewType(TypeOf(Base)) then
        begin
          Idx := 0;
          for J := 0 to High(TParamsExpr(A.left).Params) do
            Idx := Idx or Eval(TParamsExpr(A.left).Params[J]);
          if Idx <> 0 then
            Store(Base, Idx);
        end;
      end;
    end
    else if (N is TPasImplForLoop) and (TPasImplForLoop(N).LoopType = ltIn) then
    begin
      L := TPasImplForLoop(N);
      if IsViewOrPtr(TypeOf(L.VariableName)) then
        Store(L.VariableName, Eval(L.StartExpr));
    end
    else if N is TParamsExpr then
      CallEffects(TParamsExpr(N));
end;

{ One pass over the body: the roots of the locals grow; findings in the last pass. }
procedure TS28.Pass;
var
  I: Integer;
begin
  for I := 0 to FBody.Get.Count - 1 do
    Step(TPasElement(FBody.Get[I]));
end;

{ ---------- the writes of a root while a view of it lives ---------- }

{ The bit of the variable FVars[K] in a set of live variables; the variables past 62 share bit 63, always live. }
function VarBit(const K: Integer): Int64;
begin
  if K < 63 then
    Result := Int64(1) shl K
  else
    Result := Int64(1) shl 63;
end;

{ The statement (or the compound statement whose own expression) holds N. }
function OwnerOf(const N: TPasElement): TPasElement;
begin
  Result := N;
  while (Result <> nil) and not (Result is TPasImplElement) do
    Result := Result.Parent;
end;

procedure TS28.NodesOf(const El: TPasElement; const L: TFPList);
var
  I: Integer;
begin
  L.Clear;
  if El = nil then
    Exit;
  FNodes.Get.Clear;
  El.ForEachCall(@Collect, nil);
  for I := 0 to FNodes.Get.Count - 1 do
    L.Add(FNodes.Get[I]);
end;

{ The writes of the roots in the body, and the calls of the nested routines that write them (H: "how<tab>root"). }
procedure TS28.CollectWrites;
var
  Found, Decls: TListBox;
  Hows: TLinesBox;
  I, J, K, Q: Integer;
  N, R: TPasElement;
  D: TPasElement;
  How: String;
  T: TPasType;
  Escaped: TRoots;
begin
  FEvNodes.Get.Clear;
  FEvHows.Get.Clear;
  Found := TListBox.Own(TFPList.Create);
  Decls := TListBox.Own(TFPList.Create);
  Hows := TLinesBox.Own(TStringList.Create);
  VetWrites(FBody.Get, Found.Get, Decls.Get, Hows.Get);
  for I := 0 to Found.Get.Count - 1 do
  begin
    K := RootIndex(Ref(TPasElement(Decls.Get[I])));
    if K < 0 then
      K := RootIndex(TPasElement(Decls.Get[I]));
    if K > 0 then
    begin
      FEvNodes.Get.Add(Found.Get[I]);
      FEvHows.Get.Add(Hows.Get[I] + ' writes' + #9 + IntToStr(K));
    end;
  end;
  // the nested routines: what each one writes and reads of the variables of this routine
  SetLength(FNestWrites, 0);
  SetLength(FNestUses, 0);
  if FNest = nil then
    Exit;
  SetLength(FNestWrites, FNest.Count);
  SetLength(FNestUses, FNest.Count);
  for I := 0 to FNest.Count - 1 do
  begin
    FNestWrites[I] := 0;
    FNestUses[I] := 0;
    for J := 0 to FNest.Writes(I).Count - 1 do
    begin
      K := RootIndex(TPasElement(FNest.Writes(I)[J]));
      if K > 0 then
        FNestWrites[I] := FNestWrites[I] or Bit(K);
    end;
    for J := 0 to FNest.Refs(I).Count - 1 do
    begin
      K := VarIndex(TPasElement(FNest.Refs(I)[J]));
      if K >= 0 then
        FNestUses[I] := FNestUses[I] or VarBit(K);
    end;
  end;
  Escaped := 0;
  for J := 0 to FBody.Get.Count - 1 do
  begin
    N := TPasElement(FBody.Get[J]);
    if not (N is TPrimitiveExpr) then
      Continue;
    K := FNest.IndexOf(Ref(N));
    if (K < 0) or (FNestWrites[K] = 0) then
      Continue;
    if VetUseOf(N) = 'v' then
    begin
      Escaped := Escaped or FNestWrites[K];
      How := Format('%s, as a procedure value, writes', [NameOf(N)]);
    end
    else
      How := Format('the call of %s, which (or a nested routine it calls) writes', [NameOf(N)]);
    for Q := 1 to High(FRoots) do
      if FNestWrites[K] and Bit(Q) <> 0 then
      begin
        FEvNodes.Get.Add(N);
        FEvHows.Get.Add(How + #9 + IntToStr(Q));
      end;
  end;
  if Escaped = 0 then
    Exit;
  // a call of a procedure value may call a nested routine that writes
  for J := 0 to FBody.Get.Count - 1 do
  begin
    N := TPasElement(FBody.Get[J]);
    if not ((N is TParamsExpr) and (TParamsExpr(N).Kind = pekFuncParams)) then
      Continue;
    R := Ref(TParamsExpr(N).Value);
    if not ((R is TPasVariable) or (R is TPasArgument)) then
      Continue;
    T := DeclType(R);
    if not (T is TPasProcedureType) then
      Continue;
    D := N;
    for Q := 1 to High(FRoots) do
      if Escaped and Bit(Q) <> 0 then
      begin
        FEvNodes.Get.Add(D);
        FEvHows.Get.Add(Format('the call of the procedure value %s, which may be a nested routine that writes',
          [NameOf(N)]) + #9 + IntToStr(Q));
      end;
  end;
end;

{ The variables that the elements L read: a view variable named, or one a nested routine named in L reads. Skip: the
  left side of a plain assignment, which is not read. }
function TS28.UsesOf(const L: TFPList; const Skip: TPasElement): Int64;
var
  I, K: Integer;
  N, D: TPasElement;
begin
  Result := 0;
  for I := 0 to L.Count - 1 do
  begin
    N := TPasElement(L[I]);
    if not (N is TPrimitiveExpr) or (N = Skip) then
      Continue;
    D := Ref(N);
    if D = nil then
      Continue;
    K := VarIndex(D);
    if K >= 0 then
      Result := Result or VarBit(K)
    else if FNest <> nil then
    begin
      K := FNest.IndexOf(D);
      if K >= 0 then
        Result := Result or FNestUses[K];
    end;
  end;
end;

function TS28.ExprUses(const E: TPasElement): Int64;
var
  L: TListBox;
begin
  L := TListBox.Own(TFPList.Create);
  NodesOf(E, L.Get);
  Result := UsesOf(L.Get, nil);
end;

procedure TS28.Record_(const El: TPasElement; const Live: Int64);
var
  I: Integer;
begin
  I := FLiveAt.Get.IndexOf(El);
  if I < 0 then
  begin
    FLiveAt.Get.Add(El);
    SetLength(FLiveSets, FLiveAt.Get.Count);
    I := FLiveAt.Get.Count - 1;
  end;
  FLiveSets[I] := Live;
end;

{ Backward liveness: the variables that may be read after the statement El, given those read after it (Out). Records
  for each statement (and each compound statement, after its own expression) the set live right after it. Jumps (Exit,
  Break, Continue, raise) are taken as falling through, which keeps more alive. }
function TS28.Live(const El: TPasElement; const Out: Int64): Int64;
var
  I, Rounds: Integer;
  L: TListBox;
  A: TPasImplAssign;
  Def, Head, B, After, X, Save: Int64;
  K: Integer;
  T: TPasImplTry;
  Cs: TPasImplCaseOf;
  HasElse: Boolean;
begin
  Result := Out;
  if El = nil then
    Exit;
  if El is TPasImplIfElse then
  begin
    After := Live(TPasImplIfElse(El).IfBranch, Out) or Live(TPasImplIfElse(El).ElseBranch, Out);
    Record_(El, After or FExc);
    Result := After or ExprUses(TPasImplIfElse(El).ConditionExpr);
  end
  else if El is TPasImplWhileDo then
  begin
    X := ExprUses(TPasImplWhileDo(El).ConditionExpr);
    Head := X or Out;
    Rounds := 0;
    repeat
      B := Live(TPasImplWhileDo(El).Body, Head);
      After := Head;
      Head := X or Out or B;
      Inc(Rounds);
    until (Head = After) or (Rounds > 8);
    Record_(El, Out or B or FExc);
    Result := Head;
  end
  else if El is TPasImplForLoop then
  begin
    X := ExprUses(TPasImplForLoop(El).StartExpr) or ExprUses(TPasImplForLoop(El).EndExpr);
    Def := 0;
    K := VarIndex(Ref(TPasImplForLoop(El).VariableName));
    if (K >= 0) and (K < 63) then
      Def := VarBit(K);
    Head := Out;
    Rounds := 0;
    repeat
      B := Live(TPasImplForLoop(El).Body, Head) and not Def;
      After := Head;
      Head := Out or B;
      Inc(Rounds);
    until (Head = After) or (Rounds > 8);
    Record_(El, Head or FExc);
    Result := X or Head;
  end
  else if El is TPasImplRepeatUntil then
  begin
    X := ExprUses(TPasImplRepeatUntil(El).ConditionExpr);
    Head := 0;
    Rounds := 0;
    repeat
      B := X or Out or Head;
      for I := TPasImplBlock(El).Elements.Count - 1 downto 0 do
        B := Live(TPasElement(TPasImplBlock(El).Elements[I]), B);
      After := Head;
      Head := B;
      Inc(Rounds);
    until (Head = After) or (Rounds > 8);
    Record_(El, X or Out or Head or FExc);
    Result := Head;
  end
  else if El is TPasImplTry then
  begin
    T := TPasImplTry(El);
    After := Out;
    if T.ElseBranch <> nil then
      After := After or Live(T.ElseBranch, Out);
    X := 0;
    if T.FinallyExcept <> nil then
      X := Live(T.FinallyExcept, Out);
    if T.FinallyExcept is TPasImplTryFinally then
      After := X; // the end of the block goes through the finally part
    Save := FExc;
    FExc := FExc or X; // any statement of the block may go to the handler
    B := After;
    for I := T.Elements.Count - 1 downto 0 do
      B := Live(TPasElement(T.Elements[I]), B);
    FExc := Save;
    Result := B or X;
  end
  else if El is TPasImplCaseOf then
  begin
    Cs := TPasImplCaseOf(El);
    After := 0;
    HasElse := False;
    for I := 0 to Cs.Elements.Count - 1 do
      if TObject(Cs.Elements[I]) is TPasImplCaseStatement then
        After := After or Live(TPasImplCaseStatement(Cs.Elements[I]).Body, Out)
      else
      begin
        HasElse := True;
        After := After or Live(TPasElement(Cs.Elements[I]), Out);
      end;
    if not HasElse then
      After := After or Out;
    Record_(El, After or FExc);
    Result := After or ExprUses(Cs.CaseExpr);
  end
  else if El is TPasImplWithDo then
  begin
    After := Live(TPasImplWithDo(El).Body, Out);
    Record_(El, After or FExc);
    Result := After;
    for I := 0 to TPasImplWithDo(El).Expressions.Count - 1 do
      Result := Result or ExprUses(TPasElement(TPasImplWithDo(El).Expressions[I]));
  end
  else if El is TPasImplExceptOn then
    Result := Live(TPasImplExceptOn(El).Body, Out)
  else if (El is TPasImplBlock) and not (El is TPasImplStatement) then
  begin
    B := Out;
    for I := TPasImplBlock(El).Elements.Count - 1 downto 0 do
      B := Live(TPasElement(TPasImplBlock(El).Elements[I]), B);
    Result := B;
  end
  else
  begin
    // a simple statement: an assignment, a call, raise
    After := Out or FExc;
    Record_(El, After);
    L := TListBox.Own(TFPList.Create);
    NodesOf(El, L.Get);
    Def := 0;
    A := nil;
    if El is TPasImplAssign then
    begin
      A := TPasImplAssign(El);
      if (A.Kind = akDefault) and (A.left is TPrimitiveExpr) then
      begin
        K := VarIndex(Ref(A.left));
        if (K >= 0) and (K < 63) then
          Def := VarBit(K);
      end;
    end;
    if (A <> nil) and (Def <> 0) then
      Result := UsesOf(L.Get, A.left) or (After and not Def)
    else
      Result := UsesOf(L.Get, nil) or After;
  end;
end;

{ The forward effects of the elements L: the roots of the views each variable may hold grow, a plain assignment
  replaces them. }
procedure TS28.Steps(const L: TFPList);
var
  I: Integer;
begin
  for I := 0 to L.Count - 1 do
    Step(TPasElement(L[I]));
end;

procedure TS28.ExprSteps(const E: TPasElement);
var
  L: TListBox;
begin
  if E = nil then
    Exit;
  L := TListBox.Own(TFPList.Create);
  NodesOf(E, L.Get);
  Steps(L.Get);
end;

{ The writes of the roots in the statement El (or in its own expression): an error when a variable live after it may
  hold a view of the root, or when a loop for ... in over a view of it is running. }
procedure TS28.CheckAt(const El: TPasElement);
var
  I, J, K, Root: Integer;
  LiveSet: Int64;
  Parts: array of String;
  Holder: String;
begin
  if FQuietLoops > 0 then
    Exit;
  for I := 0 to FEvNodes.Get.Count - 1 do
  begin
    if OwnerOf(TPasElement(FEvNodes.Get[I])) <> El then
      Continue;
    Parts := FEvHows.Get[I].Split([#9]);
    Root := StrToInt(Parts[1]);
    J := FLiveAt.Get.IndexOf(El);
    if J >= 0 then
      LiveSet := FLiveSets[J]
    else
      LiveSet := -1;
    Holder := '';
    if FExtra and Bit(Root) <> 0 then
      Holder := 'the loop for ... in over a view of it, which reads it in its next round'
    else
      for K := 0 to High(FVars) do
        if (LiveSet and (VarBit(K) or VarBit(63)) <> 0) and (FVars[K].Roots and Bit(Root) <> 0) then
        begin
          Holder := Format('%s, which may hold a view of it, is used after the write', [FVars[K].Decl.Name]);
          Break;
        end;
    if Holder = '' then
      Continue;
    FFinal := True;
    Add(TPasElement(FEvNodes.Get[I]), Format('%s %s while a view of it lives: %s; a view holds no reference, so it '
      + 'would see changed or freed bytes (and a map of views would hold keys changed under their hashes); write it '
      + 'after the last use of its views, or keep copies of the words (W.ToString)' + SpecRef,
      [Parts[0], FRoots[Root].Name, Holder]));
    FFinal := False;
  end;
end;

procedure TS28.SaveRoots(out R: TRootsArray);
var
  I: Integer;
begin
  SetLength(R, Length(FVars));
  for I := 0 to High(FVars) do
    R[I] := FVars[I].Roots;
end;

procedure TS28.JoinRoots(const R: TRootsArray);
var
  I: Integer;
begin
  for I := 0 to High(FVars) do
    FVars[I].Roots := FVars[I].Roots or R[I];
end;

procedure TS28.LoadRoots(const R: TRootsArray);
var
  I: Integer;
begin
  for I := 0 to High(FVars) do
    FVars[I].Roots := R[I];
end;

{ Forward over the statements: what views each variable may hold at each point; CheckAt at each statement. A loop is
  walked twice from the join of its entry and the end of the last round; the first round reports nothing. }
procedure TS28.Fwd(const El: TPasElement);
var
  I, Round_: Integer;
  S0, S1: TRootsArray;
  L: TListBox;
  F: TPasImplForLoop;
  T: TPasImplTry;
  Cs: TPasImplCaseOf;
  HasElse: Boolean;
  SaveExtra: TRoots;
begin
  if El = nil then
    Exit;
  if El is TPasImplIfElse then
  begin
    ExprSteps(TPasImplIfElse(El).ConditionExpr);
    CheckAt(El);
    SaveRoots(S0);
    Fwd(TPasImplIfElse(El).IfBranch);
    SaveRoots(S1);
    LoadRoots(S0);
    Fwd(TPasImplIfElse(El).ElseBranch);
    JoinRoots(S1);
  end
  else if El is TPasImplWhileDo then
    for Round_ := 1 to 2 do
    begin
      if Round_ = 1 then
        Inc(FQuietLoops);
      SaveRoots(S0);
      ExprSteps(TPasImplWhileDo(El).ConditionExpr);
      CheckAt(El);
      Fwd(TPasImplWhileDo(El).Body);
      ExprSteps(TPasImplWhileDo(El).ConditionExpr);
      JoinRoots(S0);
      if Round_ = 1 then
        Dec(FQuietLoops);
    end
  else if El is TPasImplForLoop then
  begin
    F := TPasImplForLoop(El);
    ExprSteps(F.StartExpr);
    ExprSteps(F.EndExpr);
    SaveExtra := FExtra;
    if (F.LoopType = ltIn) and IsViewOrPtr(TypeOf(F.StartExpr)) then
      FExtra := FExtra or Eval(F.StartExpr); // the enumerator holds the views
    for Round_ := 1 to 2 do
    begin
      if Round_ = 1 then
        Inc(FQuietLoops);
      SaveRoots(S0);
      CheckAt(El);
      if (F.LoopType = ltIn) and IsViewOrPtr(TypeOf(F.VariableName)) then
      begin
        FStrong := True;
        Store(F.VariableName, Eval(F.StartExpr));
        FStrong := False;
      end;
      Fwd(F.Body);
      JoinRoots(S0);
      if Round_ = 1 then
        Dec(FQuietLoops);
    end;
    FExtra := SaveExtra;
  end
  else if El is TPasImplRepeatUntil then
    for Round_ := 1 to 2 do
    begin
      if Round_ = 1 then
        Inc(FQuietLoops);
      SaveRoots(S0);
      for I := 0 to TPasImplBlock(El).Elements.Count - 1 do
        Fwd(TPasElement(TPasImplBlock(El).Elements[I]));
      ExprSteps(TPasImplRepeatUntil(El).ConditionExpr);
      CheckAt(El);
      JoinRoots(S0);
      if Round_ = 1 then
        Dec(FQuietLoops);
    end
  else if El is TPasImplTry then
  begin
    T := TPasImplTry(El);
    SaveRoots(S0);
    for I := 0 to T.Elements.Count - 1 do
      Fwd(TPasElement(T.Elements[I]));
    // the handler may start at any point of the block
    JoinRoots(S0);
    Fwd(T.FinallyExcept);
    Fwd(T.ElseBranch);
  end
  else if El is TPasImplCaseOf then
  begin
    Cs := TPasImplCaseOf(El);
    ExprSteps(Cs.CaseExpr);
    CheckAt(El);
    SaveRoots(S0);
    SetLength(S1, Length(S0));
    for I := 0 to High(S1) do
      S1[I] := 0;
    HasElse := False;
    for I := 0 to Cs.Elements.Count - 1 do
    begin
      LoadRoots(S0);
      if TObject(Cs.Elements[I]) is TPasImplCaseStatement then
        Fwd(TPasImplCaseStatement(Cs.Elements[I]).Body)
      else
      begin
        HasElse := True;
        Fwd(TPasElement(Cs.Elements[I]));
      end;
      JoinRoots(S1);
      SaveRoots(S1);
    end;
    if not HasElse then
      JoinRoots(S0);
  end
  else if El is TPasImplWithDo then
  begin
    for I := 0 to TPasImplWithDo(El).Expressions.Count - 1 do
      ExprSteps(TPasElement(TPasImplWithDo(El).Expressions[I]));
    CheckAt(El);
    Fwd(TPasImplWithDo(El).Body);
  end
  else if El is TPasImplExceptOn then
    Fwd(TPasImplExceptOn(El).Body)
  else if (El is TPasImplBlock) and not (El is TPasImplStatement) then
  begin
    for I := 0 to TPasImplBlock(El).Elements.Count - 1 do
      Fwd(TPasElement(TPasImplBlock(El).Elements[I]));
  end
  else
  begin
    L := TListBox.Own(TFPList.Create);
    NodesOf(El, L.Get);
    Steps(L.Get);
    CheckAt(El);
  end;
end;

{ The writes of the roots while views of them live: liveness backward, the views held forward. }
procedure TS28.CheckWrites(const Block: TPasImplBlock; const Start: TRootsArray);
var
  Nest: specialize TOwned<TVetNested>;
begin
  if FProc <> nil then
  begin
    Nest := specialize TOwned<TVetNested>.Own(TVetNested.Create(FProc));
    // borrow: Nest owns it until the end of this check
    FNest := Nest.Get;
    if FNest.Count = 0 then
      FNest := nil;
  end
  else
    FNest := nil;
  CollectWrites;
  if FEvNodes.Get.Count = 0 then
  begin
    FNest := nil;
    Exit;
  end;
  FLiveAt.Get.Clear;
  SetLength(FLiveSets, 0);
  FExc := 0;
  Live(Block, 0);
  LoadRoots(Start);
  FFinal := False;
  FExtra := 0;
  FQuietLoops := 0;
  Fwd(Block);
  FFinal := True;
  FNest := nil;
end;

{ A nested routine that reads a view of this routine is called directly, not used as a procedure value. }
procedure TS28.CheckCapture;
var
  I, J, K: Integer;
  D, N, R: TPasElement;
  Reads: String;
  Nested: TListBox;
begin
  if (FProc = nil) or (FProc.Body = nil) or (Length(FVars) = 0) then
    Exit;
  for I := 0 to FProc.Body.Declarations.Count - 1 do
  begin
    D := TPasElement(FProc.Body.Declarations[I]);
    if not ((D is TPasProcedure) and (TPasProcedure(D).Body <> nil) and (TPasProcedure(D).Body.Body <> nil)) then
      Continue;
    FNodes.Get.Clear;
    TPasProcedure(D).Body.Body.ForEachCall(@Collect, nil);
    Nested := TListBox.Own(TFPList.Create);
    Nested.Get.Assign(FNodes.Get);
    Reads := '';
    for J := 0 to Nested.Get.Count - 1 do
    begin
      N := TPasElement(Nested.Get[J]);
      if N is TPrimitiveExpr then
      begin
        R := Ref(N);
        if (R <> nil) and (VarIndex(R) >= 0) then
        begin
          Reads := R.Name;
          Break;
        end;
      end;
    end;
    if Reads = '' then
      Continue;
    for K := 0 to FBody.Get.Count - 1 do
    begin
      N := TPasElement(FBody.Get[K]);
      if ((N is TUnaryExpr) and (TUnaryExpr(N).OpCode = eopAddress) and (Ref(TUnaryExpr(N).Operand) = D))
        or ((N is TPrimitiveExpr) and (Ref(N) = D) and (((N.Parent is TParamsExpr)
        and (TParamsExpr(N.Parent).Value <> N)) or ((N.Parent is TPasImplAssign)
        and (TPasImplAssign(N.Parent).right = N)))) then
        Add(N, Format('%s reads the view %s of %s and is used as a procedure value, which may run after %s returns '
          + 'and its String is gone: call it directly, or give it a copy (W.ToString)' + SpecRef,
          [D.Name, Reads, FProc.Name, FProc.Name]));
    end;
  end;
end;

{ The body of the routine FProc (or the main block, FProc = nil): the passes, then the findings. }
procedure TS28.CheckBody(const Block: TPasImplBlock);
var
  I: Integer;
  N, D: TPasElement;
  Involved: Boolean;
  Round: Integer;
begin
  FNodes.Get.Clear;
  Block.ForEachCall(@Collect, nil);
  FBody.Get.Assign(FNodes.Get);
  Involved := Length(FVars) > 0;
  I := 0;
  while not Involved and (I < FBody.Get.Count) do
  begin
    N := TPasElement(FBody.Get[I]);
    if N is TPrimitiveExpr then
    begin
      D := Ref(N);
      if (D <> nil) and IsViewDecl(D) then
        Involved := True;
    end;
    Inc(I);
  end;
  if not Involved then
    Exit;
  SaveRoots(FStart);
  FFinal := False;
  Round := 0;
  repeat
    FChanged := False;
    Pass;
    Inc(Round);
  until not FChanged or (Round >= 8);
  FFinal := True;
  Pass;
  CheckCapture;
  // the writes of the roots, flow-sensitive: from the roots of the parameters at the start
  LoadRoots(FStart);
  FStrongOK := True;
  CheckWrites(Block, FStart);
  FStrongOK := False;
end;

procedure TS28.CheckRoutine(const P: TPasProcedure);
var
  I, K: Integer;
  A: TPasArgument;
  D: TPasElement;
  Mark, Only: String;
  NCand: Integer;
  Scope: TPasProcedureScope;
begin
  if (P.Body = nil) or (P.Body.Body = nil) then
    Exit;
  // borrow: the routine belongs to the module being checked
  FProc := P;
  FDecl := nil;
  FSelfType := nil;
  if P.CustomData is TPasProcedureScope then
  begin
    Scope := TPasProcedureScope(P.CustomData);
    // borrow: the declaration belongs to the module being checked
    FDecl := Scope.DeclarationProc;
    if (Scope.ClassRecScope <> nil) and (Scope.ClassRecScope.Element is TPasRecordType)
      and IsViewType(TPasType(Scope.ClassRecScope.Element)) then
      // borrow: the type belongs to the checked module or a used unit, alive during the check
      FSelfType := TPasType(Scope.ClassRecScope.Element);
  end;
  SetLength(FRoots, 1);
  FRoots[0].Decl := nil;
  FRoots[0].Name := 'Self';
  SetLength(FVars, 0);
  FOuter := -1;
  FResultOK := 0;
  // the parameters: a String is a root, a view is a root of its own (the caller's)
  for I := 0 to P.ProcType.Args.Count - 1 do
  begin
    A := TPasArgument(P.ProcType.Args[I]);
    if (A.ArgType <> nil) and IsViewDecl(A) then
    begin
      K := Length(FVars);
      SetLength(FVars, K + 1);
      FVars[K].Decl := A;
      FVars[K].Roots := Bit(AddRoot(A, A.Name));
    end;
  end;
  for I := 0 to P.Body.Declarations.Count - 1 do
  begin
    D := TPasElement(P.Body.Declarations[I]);
    if (D.ClassType = TPasVariable) and IsViewDecl(D) then
    begin
      K := Length(FVars);
      SetLength(FVars, K + 1);
      FVars[K].Decl := D;
      FVars[K].Roots := 0;
    end;
  end;
  // the result: // root: names the parameters it is a view of
  FFinal := True;
  if IsViewDecl(P) and not IsMaker(P) then
  begin
    Mark := EffectiveMark(P);
    NCand := Candidates(P, Only);
    if FSelfType <> nil then
      FResultOK := Bit(0);
    if VetInMark(Mark, 'Self') and (FSelfType <> nil) then
      FResultOK := FResultOK or Bit(0);
    for I := 0 to P.ProcType.Args.Count - 1 do
    begin
      A := TPasArgument(P.ProcType.Args[I]);
      if not VetInMark(Mark, A.Name) then
        Continue;
      K := RootIndex(A);
      if (K < 0) and IsStringDecl(A) and (A.Access in [argDefault, argConst, argConstRef]) then
        K := AddRoot(A, A.Name);
      if K > 0 then
        FResultOK := FResultOK or Bit(K);
    end;
    if FResultOK = 0 then
    begin
      D := P;
      if FDecl <> nil then
        D := FDecl;
      if NCand = 0 then
        Add(D, Format('%s returns a view (a TStrView, or a value that holds one), but it has no String or view '
          + 'parameter (a value or const one) that the view could be a part of: return a copy (a String, a TStrSlice)'
          + SpecRef, [P.Name]))
      else if Mark = '' then
        Add(D, Format('%s returns a view (a TStrView, or a value that holds one) and has %d String or view '
          + 'parameters: name the one the view is a part of with // root: <parameter> on its header line' + SpecRef,
          [P.Name, NCand]))
      else
        Add(D, Format('the // root: mark of %s names no String or view parameter (a value or const one) of it'
          + SpecRef, [P.Name]));
    end
    else if (MarkOf(P) = '') and (NCand > 1) and Exported(P) then
    begin
      // an exported routine says it on its header: a contract for the units that call it
      Only := '';
      for I := 0 to P.ProcType.Args.Count - 1 do
        if VetInMark(Mark, TPasArgument(P.ProcType.Args[I]).Name) then
        begin
          if Only <> '' then
            Only := Only + ', ';
          Only := Only + TPasArgument(P.ProcType.Args[I]).Name;
        end;
      if Only = '' then
        Only := '<parameter>';
      D := P;
      if FDecl <> nil then
        D := FDecl;
      Add(D, Format('%s returns a view and has %d String or view parameters: an exported routine names the one the '
        + 'view is a part of with // root: %s on its header line' + SpecRef, [P.Name, NCand, Only]));
    end;
  end;
  CheckBody(P.Body.Body);
  FProc := nil;
  FDecl := nil;
  FSelfType := nil;
end;

{ The main block of a program, or an initialization or finalization section: there are no locals. }
procedure TS28.CheckMain(const Block: TPasImplBlock);
begin
  if Block = nil then
    Exit;
  FProc := nil;
  FDecl := nil;
  FSelfType := nil;
  SetLength(FRoots, 1);
  FRoots[0].Decl := nil;
  FRoots[0].Name := 'Self';
  SetLength(FVars, 0);
  FOuter := -1;
  FResultOK := 0;
  CheckBody(Block);
end;

{ The fields of classes and the globals of a view type (where they are declared), and the routines. }
procedure TS28.CheckDecls(const Decls: TPasDeclarations; const Top: Boolean);
var
  I: Integer;
  D: TPasElement;

  procedure Members(const C: TPasClassType);
  var
    J: Integer;
    M: TPasElement;
  begin
    for J := 0 to C.Members.Count - 1 do
    begin
      M := TPasElement(C.Members[J]);
      if M is TPasClassType then
        Members(TPasClassType(M))
      else if (M.ClassType = TPasVariable) and IsViewDecl(M) then
      begin
        FFinal := True;
        FFlagged.Get.Add(M);
        Add(M, Format('the field %s of the class %s holds a view (a TStrView, or a value that holds one): an object '
          + 'outlives the routine, and a view holds no reference to its String; keep a copy (a String, a TStrSlice)'
          + SpecRef, [M.Name, C.Name]));
      end;
    end;
  end;

begin
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    D := TPasElement(Decls.Declarations[I]);
    if D is TPasClassType then
    begin
      if not TPasClassType(D).IsForward then
        Members(TPasClassType(D));
    end
    else if Top and (D.ClassType = TPasVariable) and IsViewDecl(D) then
    begin
      FFinal := True;
      FFlagged.Get.Add(D);
      Add(D, Format('the global (or threadvar) %s holds a view (a TStrView, or a value that holds one): a global '
        + 'outlives every routine, and a view holds no reference to its String; keep views in locals, or keep a '
        + 'copy (a String, a TStrSlice)' + SpecRef, [D.Name]));
    end
    else if D is TPasProcedure then
    begin
      CheckRoutine(TPasProcedure(D));
      if TPasProcedure(D).Body <> nil then
        CheckDecls(TPasProcedure(D).Body, False); // nested routines
    end;
  end;
end;

{ A routine of Decls (or nested in one) returns a view, has several candidates and no written // root: mark. }
function TS28.NeedsInference(const Decls: TPasDeclarations): Boolean;
var
  I: Integer;
  D: TPasElement;
  Only: String;
begin
  Result := False;
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    D := TPasElement(Decls.Declarations[I]);
    if not ((D is TPasProcedure) and (TPasProcedure(D).Body <> nil)) then
      Continue;
    if IsViewDecl(D) and not IsMaker(D) and (Candidates(TPasProcedure(D), Only) > 1)
      and (MarkOf(TPasProcedure(D)) = '') then
      Exit(True);
    if NeedsInference(TPasProcedure(D).Body) then
      Exit(True);
  end;
end;

procedure TS28.Flush(var Report: TVetReport);
var
  I: Integer;
begin
  for I := 0 to High(FReport.Findings) do
    with FReport.Findings[I] do
      VetAdd(Report, FileName, Row, Col, Severity, Rule, Msg);
end;

procedure VetCheckS28(const Src: TVetSource; const Module: TPasModule; const Resolver: TPasResolver;
  var Report: TVetReport);
var
  S: TS28Box;
  I, Round: Integer;
begin
  for I := 0 to High(Src.Lines) do
    if Pos('// UNSAFE-UNIT:', Src.Lines[I]) = 1 then
      Exit;
  S := TS28Box.Own(TS28.Create(Src, Resolver, Module));
  // the inference: the // root: names of the routines with several candidates and no mark grow until none changes
  if S.Get.NeedsInference(Module.ImplementationSection) or ((Module is TPasProgram)
    and S.Get.NeedsInference(TPasProgram(Module).ProgramSection)) then
  begin
    S.Get.FInfer := True;
    Round := 0;
    repeat
      S.Get.FInferChanged := False;
      S.Get.CheckDecls(Module.InterfaceSection, True);
      S.Get.CheckDecls(Module.ImplementationSection, True);
      if Module is TPasProgram then
        S.Get.CheckDecls(TPasProgram(Module).ProgramSection, True);
      Inc(Round);
    until not S.Get.FInferChanged or (Round >= 8);
    S.Get.FInfer := False;
    S.Get.FFlagged.Get.Clear;
  end;
  S.Get.CheckDecls(Module.InterfaceSection, True);
  S.Get.CheckDecls(Module.ImplementationSection, True);
  if Module is TPasProgram then
  begin
    S.Get.CheckDecls(TPasProgram(Module).ProgramSection, True);
    S.Get.CheckMain(Module.InitializationSection);
  end
  else
  begin
    S.Get.CheckMain(Module.InitializationSection);
    S.Get.CheckMain(Module.FinalizationSection);
  end;
  S.Get.Flush(Report);
end;

end.
