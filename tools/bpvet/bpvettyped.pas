{ SPDX-License-Identifier: MIT }
{ bpvet typed mode (safe/SPEC.md §20, step 6 of unxed/bp#108): resolves a module with PasResolver of fcl-passrc, the
  units it uses included, so that rules can see types. The RTL is read from declaration stubs
  (tools/bpvet/resolver/genstubs.py); the resolver is the one of FPC 3.2.2 with tools/bpvet/resolver/pasresolver.patch
  (tools/bpvet/build.sh). The resolver only resolves: where it is stricter than FPC (casts, PChar to String), bpvet
  accepts, since type errors are the job of the compiler. }
unit BpvetTyped;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Contnrs, PasTree, PScanner, PParser, PasResolveEval, PasResolver, BpvetCore, BpvetS17, BpvetRace, BpvetNil,
  BpvetCast, BpvetHold, Safe;

{ Resolves the module of Src and checks it with S17 (bpvets17.pas): True when it and every unit it uses resolve;
  otherwise a fatal with the position is in Report. UnitDirs are searched for the used units after RtlDir (the stubs), then the directory of the file.
  Implicit: units the module uses without naming them (fpc -Fa), except the module itself. }
function VetResolve(const Src: TVetSource; const RtlDir: String; const Defines, IncludeDirs, UnitDirs,
  Implicit: array of String; var Report: TVetReport): Boolean;

implementation

type
  TVetSession = class;

  { One module: its scanner, parser and resolver. The session holds every module of one check. }
  TVetResolver = class(TPasResolver)
  private
    FFileName: String;
    FFailed: Boolean; // did not resolve: not used again
    FUsed: Boolean;   // read as a used unit (its interface only): the session gives it to every module that uses it
    FSession: TVetSession; // borrow: the session that holds this resolver
    FFiles: specialize TOwned<TFileResolver>;
    FScanner: specialize TOwned<TPascalScanner>;
    FParser: specialize TOwned<TPasParser>;
    function AnyCompat(Proc: TResElDataBuiltInProc; Expr: TPasExpr; RaiseOnError: Boolean): Integer;
    procedure SizeResult(Proc: TResElDataBuiltInProc; Params: TParamsExpr; out ResolvedEl: TPasResolverResult);
    procedure FinishAny(Proc: TResElDataBuiltInProc; Params: TParamsExpr);
    procedure EvalNone(Proc: TResElDataBuiltInProc; Params: TParamsExpr; Flags: TResEvalFlags;
      out Evaluated: TResEvalValue);
    function CopyCompat(Proc: TResElDataBuiltInProc; Expr: TPasExpr; RaiseOnError: Boolean): Integer;
    procedure CopyResult(Proc: TResElDataBuiltInProc; Params: TParamsExpr; out ResolvedEl: TPasResolverResult);
    function EvalFunc(Sender: TCondDirectiveEvaluator; Name, Param: String; out Value: String): Boolean;
  public
    constructor Create(const ASession: TVetSession; const AFileName: String);
    destructor Destroy; override;
    function Parser: TPasParser;
    function FindUnit(const AName, InFilename: String; NameExpr, InFileExpr: TPasExpr): TPasModule; override;
    function CheckTypeCastRes(const FromResolved, ToResolved: TPasResolverResult; ErrorEl: TPasElement;
      RaiseOnError: Boolean): Integer; override;
    function CheckAssignCompatibilityCustom(const LHS, RHS: TPasResolverResult; ErrorEl: TPasElement;
      RaiseOnIncompatible: Boolean; var Handled: Boolean): Integer; override;
  end;

  TVetSession = class
  public
    Hub: specialize TOwned<TPasResolverHub>;
    Modules: specialize TOwned<TObjectList>;  // of TVetResolver, owned
    SearchDirs, Defines: array of String;     // the last search directory: that of the checked file
    UnitError: String;                        // the first failure of a used unit in the current check
    function FindFile(const AName: String): String;
    function Loaded(const AName: String): TVetResolver;
  end;


const
  { compiler magic with variable arguments: accepted with any arguments }
  MagicProcs: array[0..9] of String = ('Write', 'WriteLn', 'Read', 'ReadLn', 'Halt', 'Randomize', 'Initialize',
    'Finalize', 'FinalizeArray', 'SetString');
  MagicFuncs: array[0..4] of String = ('SizeOf', 'IsManagedType', 'Abs', 'Trunc', 'Round');
  TargetDefines: array[0..6] of String = ('FPC', 'LINUX', 'UNIX', 'CPUX86_64', 'CPU64', 'ENDIAN_LITTLE',
    'FPC_HAS_FEATURE_DYNARRAYS');

{ ---------- the session ---------- }

function TVetSession.FindFile(const AName: String): String;
var
  I: Integer;
  F: String;
begin
  for I := 0 to High(SearchDirs) do
  begin
    F := IncludeTrailingPathDelimiter(SearchDirs[I]) + LowerCase(AName) + '.pp';
    if FileExists(F) then
      Exit(F);
    F := ChangeFileExt(F, '.pas');
    if FileExists(F) then
      Exit(F);
  end;
  Result := '';
end;

function TVetSession.Loaded(const AName: String): TVetResolver;
var
  I: Integer;
  R: TVetResolver;
begin
  for I := 0 to Modules.Get.Count - 1 do
  begin
    R := TVetResolver(Modules.Get[I]);
    if R.FUsed and not R.FFailed and (CompareText(ChangeFileExt(ExtractFileName(R.FFileName), ''), AName) = 0) then
      Exit(R);
  end;
  Result := nil;
end;

{ ---------- one module ---------- }

constructor TVetResolver.Create(const ASession: TVetSession; const AFileName: String);
var
  I: Integer;
  N: String;
begin
  inherited Create;
  // borrow: the session holds this resolver in its list, so it outlives it
  FSession := ASession;
  FFileName := AFileName;
  // borrow: the hub belongs to the session, which outlives this resolver
  Hub := ASession.Hub.Get;
  AddObjFPCBuiltInIdentifiers(btAllFPCTypes, bfAllStandardProcs - [bfCopyArray]);
  for N in MagicProcs do
    AddBuiltInProc(N, N + '(any)', @AnyCompat, nil, nil, @FinishAny, bfCustom, [bipfCanBeStatement]);
  for N in MagicFuncs do
    AddBuiltInProc(N, N + '(any): SizeInt', @AnyCompat, @SizeResult, @EvalNone, @FinishAny);
  AddBuiltInProc('Copy', 'function Copy(const StringOrArray; Start, Count: SizeInt): StringOrArray', @CopyCompat,
    @CopyResult, nil, nil, bfCopyArray);
  FFiles := specialize TOwned<TFileResolver>.Own(VetNewFileResolver);
  for I := 0 to High(ASession.SearchDirs) do
    FFiles.Get.AddIncludePath(ASession.SearchDirs[I]);
  FScanner := specialize TOwned<TPascalScanner>.Own(TPascalScanner.Create(FFiles.Get));
  for N in TargetDefines do
    FScanner.Get.AddDefine(N);
  for I := 0 to High(ASession.Defines) do
    FScanner.Get.AddDefine(ASession.Defines[I]);
  FScanner.Get.CurrentModeSwitches := OBJFPCModeSwitches;
  FScanner.Get.OnEvalFunction := @EvalFunc;
  FParser := specialize TOwned<TPasParser>.Own(TPasParser.Create(FScanner.Get, FFiles.Get, Self));
  FParser.Get.Options := FParser.Get.Options + [po_ResolveStandardTypes, po_KeepClassForward];
end;

destructor TVetResolver.Destroy;
begin
  FParser.Reset;
  FScanner.Reset;
  FFiles.Reset;
  inherited Destroy;
end;

function TVetResolver.Parser: TPasParser;
begin
  Result := FParser.Get;
end;

// UNSAFE: keep the parameter modes of the fcl-passrc callback type
function TVetResolver.EvalFunc(Sender: TCondDirectiveEvaluator; Name, Param: String; out Value: String): Boolean;
begin
  // declared(X), defined(X) of compiler-internal symbols: "no"; sizeof: 8 (the target is x86_64)
  if CompareText(Name, 'sizeof') = 0 then
    Value := '8'
  else
    Value := '0';
  Result := True;
end;

// UNSAFE: keep the parameter modes of the fcl-passrc callback type
function TVetResolver.AnyCompat(Proc: TResElDataBuiltInProc; Expr: TPasExpr; RaiseOnError: Boolean): Integer;
var
  I: Integer;
  R: TPasResolverResult;
begin
  if Expr is TParamsExpr then
    for I := 0 to Length(TParamsExpr(Expr).Params) - 1 do
      ComputeElement(TParamsExpr(Expr).Params[I], R, []);
  Result := cExact;
end;

// UNSAFE: keep the parameter modes of the fcl-passrc callback type
procedure TVetResolver.SizeResult(Proc: TResElDataBuiltInProc; Params: TParamsExpr;
  out ResolvedEl: TPasResolverResult);
begin
  SetResolverIdentifier(ResolvedEl, btInt64, Proc.Proc, BaseTypes[btInt64], BaseTypes[btInt64], [rrfReadable]);
end;

// UNSAFE: keep the parameter modes of the fcl-passrc callback type
procedure TVetResolver.FinishAny(Proc: TResElDataBuiltInProc; Params: TParamsExpr);
var
  I: Integer;
begin
  for I := 0 to Length(Params.Params) - 1 do
    FinishCallArgAccess(Params.Params[I], rraRead);
end;

// UNSAFE: keep the parameter modes of the fcl-passrc callback type
procedure TVetResolver.EvalNone(Proc: TResElDataBuiltInProc; Params: TParamsExpr; Flags: TResEvalFlags;
  out Evaluated: TResEvalValue);
begin
  // Without an evaluator the resolver stops with "not yet implemented" as soon as it folds an expression that holds
  // the call (I := Round(X)); the value of the call is not a constant here
  Evaluated := nil;
end;

function TVetResolver.CopyCompat(Proc: TResElDataBuiltInProc; Expr: TPasExpr; RaiseOnError: Boolean): Integer;
var
  R: TPasResolverResult;
begin
  // Copy of a string is a compiler procedure of FPC, Copy of a dynamic array the built-in of the resolver
  ComputeElement(TParamsExpr(Expr).Params[0], R, []);
  if R.BaseType in btAllStrings then
    Result := AnyCompat(Proc, Expr, RaiseOnError)
  else
    Result := BI_CopyArray_OnGetCallCompatibility(Proc, Expr, RaiseOnError);
end;

procedure TVetResolver.CopyResult(Proc: TResElDataBuiltInProc; Params: TParamsExpr;
  out ResolvedEl: TPasResolverResult);
begin
  ComputeElement(Params.Params[0], ResolvedEl, []);
  if ResolvedEl.BaseType in btAllStrings then
    ResolvedEl.Flags := [rrfReadable]
  else
    BI_CopyArray_OnGetCallResult(Proc, Params, ResolvedEl);
end;

function TVetResolver.CheckTypeCastRes(const FromResolved, ToResolved: TPasResolverResult; ErrorEl: TPasElement;
  // UNSAFE: keep the parameter modes required by the fcl-passrc override
  RaiseOnError: Boolean): Integer;
begin
  // FPC has checked the cast; bpvet needs only the resulting type
  Result := inherited CheckTypeCastRes(FromResolved, ToResolved, ErrorEl, False);
  if Result = cIncompatible then
    Result := cExact;
end;

// UNSAFE: keep the parameter modes required by the fcl-passrc override
function TVetResolver.CheckAssignCompatibilityCustom(const LHS, RHS: TPasResolverResult; ErrorEl: TPasElement;
  // UNSAFE: keep the parameter modes required by the fcl-passrc override
  RaiseOnIncompatible: Boolean; var Handled: Boolean): Integer;
begin
  // FPC converts PChar to a string implicitly
  Result := cIncompatible;
  if (LHS.BaseType in btAllStrings) and (RHS.LoTypeEl is TPasPointerType) then
  begin
    Handled := True;
    Result := cExact;
  end;
end;

// UNSAFE: keep the parameter modes required by the fcl-passrc override
function TVetResolver.FindUnit(const AName, InFilename: String; NameExpr, InFileExpr: TPasExpr): TPasModule;
var
  R: TVetResolver;
  F: String;
  M: TPasModule;
begin
  R := FSession.Loaded(AName);
  if R <> nil then
    Exit(R.RootElement as TPasModule);
  F := FSession.FindFile(AName);
  if F = '' then
    Exit(nil);
  // UNSAFE: the session list owns the resolver (TObjectList with OwnsObjects)
  R := TVetResolver.Create(FSession, F);
  FSession.Modules.Get.Add(R);
  R.Parser.Options := R.Parser.Options + [po_StopOnUnitInterface];
  R.FUsed := True;
  R.InterfaceOnly := True; // the implementation of a used unit is not read: rules use its interface only
  if CompareText(AName, 'system') = 0 then
    R.Parser.ImplicitUses.Clear;
  M := nil;
  try
    R.FScanner.Get.OpenFile(F);
    R.Parser.NextToken;
    R.Parser.ParseUnit(M);
  except
    on E: Exception do
    begin
      R.FFailed := True;
      if FSession.UnitError = '' then
        FSession.UnitError := Format('%s: %s', [F, E.Message]);
    end;
  end;
  Result := M;
end;

{ ---------- the check ---------- }

procedure AddFatal(var Report: TVetReport; const FileName: String; const ARow, ACol: Integer; const Msg: String);
begin
  VetAdd(Report, FileName, ARow, ACol, vsFatal, '', 'bpvet cannot resolve this file: ' + Msg);
end;

var
  { One session for the whole run: a used unit is read once (safe/SPEC.md §16, the tools are as fast as the compiler).
    The options are those of the first call; bpvet passes the same ones for every file.
    It is not freed: the process ends after the last check, and the teardown of the trees and the data of
    fcl-passrc with many units read crashes in ClearResolveDataList (a record of the data list is already reused);
    skipping it also saves the walk over every tree at exit. }
  // borrow: the process owns it until it ends; the OS frees it
  Shared: TVetSession = nil;

function VetSession(const RtlDir: String; const Defines, IncludeDirs, UnitDirs: array of String): TVetSession;
var
  I, N: Integer;
  S: TVetSession;
begin
  if Shared = nil then
  begin
    // UNSAFE: the session of the run, never freed (see Shared)
    Shared := TVetSession.Create;
    S := Shared;
    S.Hub := specialize TOwned<TPasResolverHub>.Own(TPasResolverHub.Create(nil));
    S.Modules := specialize TOwned<TObjectList>.Own(TObjectList.Create(True));
    SetLength(S.SearchDirs, 2 + Length(UnitDirs) + Length(IncludeDirs));
    N := 0;
    S.SearchDirs[N] := RtlDir;
    Inc(N);
    for I := 0 to High(UnitDirs) do
    begin
      S.SearchDirs[N] := UnitDirs[I];
      Inc(N);
    end;
    for I := 0 to High(IncludeDirs) do
    begin
      S.SearchDirs[N] := IncludeDirs[I];
      Inc(N);
    end;
    SetLength(S.Defines, Length(Defines));
    for I := 0 to High(Defines) do
      S.Defines[I] := Defines[I];
  end;
  Result := Shared;
end;

function VetResolve(const Src: TVetSource; const RtlDir: String; const Defines, IncludeDirs, UnitDirs,
  Implicit: array of String; var Report: TVetReport): Boolean;
var
  S: TVetSession;
  Main, R: TVetResolver;
  M: TPasModule;
  Sec: TPasSection;
  I: Integer;
  Found: Boolean;
  El: TPasElement;
  FileName: String;
begin
  Result := False;
  FileName := Src.FileName;
  S := VetSession(RtlDir, Defines, IncludeDirs, UnitDirs);
  S.SearchDirs[High(S.SearchDirs)] := ExtractFileDir(ExpandFileName(FileName));
  S.UnitError := '';
  // UNSAFE: the session list owns the resolver (TObjectList with OwnsObjects)
  Main := TVetResolver.Create(S, FileName);
  S.Modules.Get.Add(Main);
  for I := 0 to High(Implicit) do
    if CompareText(Implicit[I], ChangeFileExt(ExtractFileName(FileName), '')) <> 0 then
      Main.Parser.ImplicitUses.Add(Implicit[I]);
  try
    Main.FScanner.Get.OpenFile(FileName);
    Main.Parser.ParseMain(M);
    repeat
      Found := False;
      for I := 0 to S.Modules.Get.Count - 1 do
      begin
        R := TVetResolver(S.Modules.Get[I]);
        if not R.FFailed and R.Parser.CanParseContinue(Sec) and ((R = Main) or (Sec = nil)) then
        begin
          Found := True;
          R.Parser.ParseContinue;
          Break;
        end;
      end;
    until not Found;
    Result := True;
  except
    on E: EParserError do
      AddFatal(Report, E.Filename, E.Row, E.Column, E.Message);
    on E: EPasResolve do
    begin
      El := E.PasElement;
      if (El <> nil) and (El.SourceFilename <> '') then
        AddFatal(Report, El.SourceFilename, El.SourceLinenumber, 1, E.Message)
      else
        AddFatal(Report, Main.FScanner.Get.CurFilename, Main.FScanner.Get.CurRow, 1, E.Message);
    end;
    on E: Exception do
      AddFatal(Report, Main.FScanner.Get.CurFilename, Main.FScanner.Get.CurRow, 1, E.ClassName + ': ' + E.Message);
  end;
  if Result and (S.UnitError <> '') then
  begin
    AddFatal(Report, FileName, 1, 1, 'a used unit: ' + S.UnitError);
    Result := False;
  end;
  if Result then
  begin
    VetCheckS17(Src, M, Main, Report);
    VetCheckRaces(Src, M, Main, Report);
    VetCheckNil(Src, M, Main, Report);
    VetCheckCasts(Src, M, Main, Report);
    VetCheckHold(Src, M, Main, Report);
  end;
  if not Result then
    // the main module and every unit left unfinished by the failure are not used again
    for I := 0 to S.Modules.Get.Count - 1 do
    begin
      R := TVetResolver(S.Modules.Get[I]);
      if (R = Main) or (R.Parser.CurModule <> nil) then
        R.FFailed := True;
    end;
end;

end.
