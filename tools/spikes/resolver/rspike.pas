{ SPDX-License-Identifier: MIT }
{ Spike 1 of unxed/bp#108: can PasResolver of fcl-passrc resolve the modules of Better Pascal? (safe/SPEC.md §20)
  usage: rspike FILE SEARCHDIR...   (the first SEARCHDIR is normally the stub directory; see run.sh)
  Prints OK or FAIL with the first error. Not used by CI; the verdict is in safe/SPEC.md §20 "Spike 1 result". }
{$mode objfpc}{$H+}
program rspike;
uses SysUtils, Classes, Contnrs, PasTree, PScanner, PParser, PasResolver, PasResolveEval;

type
  TEngine = class;
  TEngine = class(TPasResolver)
  public
    FileName: String;
    Scanner: TPascalScanner;
    Parser: TPasParser;
    Resolver: TFileResolver;
    function AnyCompat(Proc: TResElDataBuiltInProc; Expr: TPasExpr; RaiseOnError: boolean): integer;
    procedure SizeResult(Proc: TResElDataBuiltInProc; Params: TParamsExpr; out ResolvedEl: TPasResolverResult);
    procedure FinishAny(Proc: TResElDataBuiltInProc; Params: TParamsExpr);
    procedure AddCompilerMagic;
    function CheckTypeCastRes(const FromResolved, ToResolved: TPasResolverResult; ErrorEl: TPasElement; RaiseOnError: boolean): integer; override;
    function CheckAssignCompatibilityCustom(const LHS, RHS: TPasResolverResult; ErrorEl: TPasElement; RaiseOnIncompatible: boolean; var Handled: boolean): integer; override;
    function EvalFunc(Sender: TCondDirectiveEvaluator; Name, Param: String; out Value: string): boolean;
    function FindUnit(const AName, InFilename: String; NameExpr, InFileExpr: TPasExpr): TPasModule; override;
  end;

var
  Relaxed: Integer = 0;
  LastResult: TPasResolverResult;
  Engines: TObjectList;
  Paths: TStringList;
  Hub: TPasResolverHub;
  Failed: TStringList;

function FindFile(const AName: String): String;
var I: Integer; F: String;
begin
  for I := 0 to Paths.Count - 1 do
  begin
    F := IncludeTrailingPathDelimiter(Paths[I]) + LowerCase(AName) + '.pp';
    if FileExists(F) then Exit(F);
    F := ChangeFileExt(F, '.pas');
    if FileExists(F) then Exit(F);
  end;
  Result := '';
end;

function TEngine.EvalFunc(Sender: TCondDirectiveEvaluator; Name, Param: String; out Value: string): boolean;
begin
  // declared(X), defined(X) for compiler-internal symbols: answer "no", sizeof: 8
  if CompareText(Name, 'sizeof') = 0 then Value := '8' else Value := '0';
  Result := True;
end;

function TEngine.AnyCompat(Proc: TResElDataBuiltInProc; Expr: TPasExpr; RaiseOnError: boolean): integer;
var I: Integer;
begin
  // compiler magic with variable arguments: resolve the arguments, accept any
  if Expr is TParamsExpr then
    for I := 0 to Length(TParamsExpr(Expr).Params) - 1 do
      ComputeElement(TParamsExpr(Expr).Params[I], LastResult, []);
  Result := cExact;
end;

procedure TEngine.SizeResult(Proc: TResElDataBuiltInProc; Params: TParamsExpr; out ResolvedEl: TPasResolverResult);
begin
  SetResolverIdentifier(ResolvedEl, btInt64, Proc.Proc, BaseTypes[btInt64], BaseTypes[btInt64], [rrfReadable]);
end;

procedure TEngine.FinishAny(Proc: TResElDataBuiltInProc; Params: TParamsExpr);
var I: Integer;
begin
  for I := 0 to Length(Params.Params) - 1 do FinishCallArgAccess(Params.Params[I], rraRead);
end;

procedure TEngine.AddCompilerMagic;
const Procs: array[0..8] of String = ('Write', 'WriteLn', 'Read', 'ReadLn', 'Halt', 'Randomize', 'Initialize', 'Finalize', 'FinalizeArray');
const Funcs: array[0..5] of String = ('SizeOf', 'IsManagedType', 'Abs', 'Random', 'Trunc', 'Round');
var N: String;
begin
  for N in Procs do AddBuiltInProc(N, N + '(any)', @AnyCompat, nil, nil, @FinishAny, bfCustom, [bipfCanBeStatement]);
  for N in Funcs do AddBuiltInProc(N, N + '(any): SizeInt', @AnyCompat, @SizeResult, nil, @FinishAny);
end;

function TEngine.CheckTypeCastRes(const FromResolved, ToResolved: TPasResolverResult; ErrorEl: TPasElement; RaiseOnError: boolean): integer;
begin
  // FPC has already checked the cast; the resolver here only needs the resulting type
  Result := inherited CheckTypeCastRes(FromResolved, ToResolved, ErrorEl, False);
  if Result = cIncompatible then begin Inc(Relaxed); Result := cExact; end;
end;

function TEngine.CheckAssignCompatibilityCustom(const LHS, RHS: TPasResolverResult; ErrorEl: TPasElement; RaiseOnIncompatible: boolean; var Handled: boolean): integer;
begin
  // FPC converts PChar to a string implicitly
  Result := cIncompatible;
  if (LHS.BaseType in btAllStrings) and (RHS.LoTypeEl is TPasPointerType) then
  begin Handled := True; Inc(Relaxed); Result := cExact; end;
end;

procedure SetupEngine(E: TEngine);
var I: Integer;
begin
  E.Hub := Hub;
  E.AddObjFPCBuiltInIdentifiers;
  E.AddCompilerMagic;
  E.Resolver := TFileResolver.Create;
  for I := 0 to Paths.Count - 1 do E.Resolver.AddIncludePath(Paths[I]);
  E.Scanner := TPascalScanner.Create(E.Resolver);
  E.Scanner.AddDefine('FPC'); E.Scanner.AddDefine('LINUX'); E.Scanner.AddDefine('UNIX');
  E.Scanner.AddDefine('CPUX86_64'); E.Scanner.AddDefine('CPU64'); E.Scanner.AddDefine('ENDIAN_LITTLE');
  E.Scanner.AddDefine('FPC_HAS_FEATURE_DYNARRAYS');
  E.Scanner.CurrentModeSwitches := OBJFPCModeSwitches;
  E.Scanner.OnEvalFunction := @E.EvalFunc;
  E.Parser := TPasParser.Create(E.Scanner, E.Resolver, E);
  E.Parser.Options := E.Parser.Options + [po_ResolveStandardTypes, po_KeepClassForward];
end;

function TEngine.FindUnit(const AName, InFilename: String; NameExpr, InFileExpr: TPasExpr): TPasModule;
var I: Integer; E: TEngine; F: String; UM: TPasModule;
begin
  UM := nil;
  for I := 0 to Engines.Count - 1 do
    if CompareText(ChangeFileExt(ExtractFileName(TEngine(Engines[I]).FileName), ''), AName) = 0 then
      Exit(TEngine(Engines[I]).RootElement as TPasModule);
  F := FindFile(AName);
  if F = '' then Exit(nil);
  E := TEngine.Create; E.FileName := F; Engines.Add(E);
  SetupEngine(E);
  E.Parser.Options := E.Parser.Options + [po_StopOnUnitInterface];
  if CompareText(AName, 'system') = 0 then E.Parser.ImplicitUses.Clear;
  try
    E.Scanner.OpenFile(F);
    E.Parser.NextToken;
    E.Parser.ParseUnit(UM);
  except
    on Ex: Exception do begin Failed.Add(Format('%s: %s', [F, Ex.Message])); end;
  end;
  Result := UM;
end;

procedure Check(const F: String);
var E: TEngine; I: Integer; Found: Boolean; Sec: TPasSection; M: TPasModule;
begin
  E := TEngine.Create; E.FileName := F; Engines.Add(E);
  SetupEngine(E);
  try
    E.Scanner.OpenFile(F);
    E.Parser.ParseMain(M);
    repeat
      Found := False;
      for I := 0 to Engines.Count - 1 do
        with TEngine(Engines[I]) do
          if (Parser <> nil) and Parser.CanParseContinue(Sec) and ((I = 0) or (Sec = nil)) then
          begin Found := True; Parser.ParseContinue; Break; end;
    until not Found;
    WriteLn('OK    ', F);
  except
    on Ex: EParserError do WriteLn('FAIL  ', Ex.Filename, '(', Ex.Row, ',', Ex.Column, ') ', Ex.Message);
    on Ex: EPasResolve do
    begin
      WriteLn('FAIL  ', F, ' ', Ex.Message, ' at ', E.GetElementSourcePosStr(Ex.PasElement));
      for I := 0 to Engines.Count - 1 do
        with TEngine(Engines[I]) do WriteLn('    scanner ', Scanner.CurFilename, ':', Scanner.CurRow);
    end;
    on Ex: Exception do WriteLn('FAIL  ', F, ' ', Ex.ClassName, ': ', Ex.Message, ' @', E.Scanner.CurFilename, ':', E.Scanner.CurRow);
  end;
end;

var I: Integer;
begin
  Engines := TObjectList.Create(False);
  Paths := TStringList.Create; Failed := TStringList.Create;
  Hub := TPasResolverHub.Create(nil);
  for I := 2 to ParamCount do Paths.Add(ParamStr(I));
  Check(ParamStr(1));
  WriteLn('  relaxed casts: ', Relaxed);
  for I := 0 to Failed.Count - 1 do WriteLn('  unit: ', Failed[I]);
  for I := 0 to Engines.Count - 1 do WriteLn('  eng: ', TEngine(Engines[I]).FileName);
end.
