{ SPDX-License-Identifier: MIT }
{ bpvet: the linter of Better Pascal for the rules that the compiler cannot check (safe/SPEC.md §6).
  Built by tools/bpvet/build.sh (FPC with fcl-passrc); it reads the sources only, no other unit is needed (the typed
  mode reads the RTL from declaration stubs).

  usage: bpvet [--report|--strict] [--fix] [--typed --rtl DIR [-FaUNIT]...] [-dNAME]... [-FiDIR]... [-FuDIR]...
               [--cache DIR [--salt TEXT]] FILE|DIR...
         bpvet --stubkey FILE|DIR...   the text the RTL stubs of FILE|DIR depend on (bpvetkey.pas), for tools/bp
         bpvet --buildkey SALT FILE|DIR... -- STAT...   the key of the stubs and the key of the check (bpvetkey.pas)
    a directory is walked for *.pas, *.pp, *.lpr (include files are read through the modules that include them);
    -dNAME defines a symbol for conditional compilation, -FiDIR adds an include directory (as for fpc);
    -FuDIR adds a directory where rule S5 looks for the files of used units (their classes);
    the target for conditional compilation is linux, x86_64;
    --typed resolves every file with the units it uses (bpvettyped.pas): the used units are looked up in the
    --rtl directory (declaration stubs of the RTL, tools/bpvet/resolver/genstubs.py), the -Fu and -Fi directories
    and the directory of the file; a file that does not resolve is reported as Fatal; -FaUNIT: a unit every file
    uses without naming it (as for fpc);
    --cache DIR keeps the findings of each file in DIR under a key of what its check reads, and does not check a file
    again while its key stays the same (bpvetcache.pas); --salt TEXT goes into every key: what the checks read besides
    the files of the program (tools/bp gives the key of the RTL stubs). Not used with --fix;
  Messages are those of FPC, one line each, so that an IDE and a model read them as compiler messages:
    FILE(LINE,COL) Error: SAFE-Sxx <what is wrong>; <how to fix it>
  Modes (the migration modes of §6):
    default   errors fail, warnings are printed
    --report  every finding is printed as a warning, the exit code is 0: the list for a migration
    --strict  warnings are errors too
  Exit code: 0 clean, 1 errors, 2 a file cannot be read or parsed, or a usage error.
  Parser limit (fcl-passrc 3.2.2): external with a one-character library name literal (external 'c')
  does not parse and is reported as Fatal; give the library name as a constant (const LibC = 'c').
  The directive nostackframe, which that parser does not know, is skipped (bpvetcore.pas, TVetLineReader).
  Rules: S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, S15, S16 (bpvetrules.pas); S17 (bpvets17.pas, typed);
  S11m, S11s, S19 (bpvetrace.pas, typed); S24, S25 (bpvetcast.pas, typed); S26a, S26b (bpvetnil.pas, typed);
  S6 and S17 of the calls of Hold of a scope or a region, S5, S6 and S17 of the tree of TComponent, S27 (bpvethold.pas,
  typed); S28, a view of a String does not outlive it (bpvets28.pas, typed);
  S21, S22 (bpvetstyle.pas, over the text, before the parse). --fix writes the fixes of S17, S21, S22 and S24 into the files. }
program bpvet;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, PasTree, BpvetCore, BpvetRules, BpvetTyped, BpvetS17, BpvetStyle, BpvetCast, BpvetKey, BpvetCache,
  Safe;

type
  TListBox = specialize TOwned<TStringList>;
  TNames = array of String;

procedure Usage;
begin
  WriteLn('usage: bpvet [--report|--strict] [--fix] [--typed --rtl DIR [-FaUNIT]...] [-dNAME]... [-FiDIR]... [-FuDIR]...');
  WriteLn('             [--cache DIR [--salt TEXT]] FILE|DIR...');
  WriteLn('  default: errors fail; --report: everything is a warning, exit code 0; --strict: warnings are errors');
end;

procedure AddTo(var A: TNames; const S: String);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)] := S;
end;

function IsSource(const Name: String): Boolean;
var
  Ext: String;
begin
  Ext := LowerCase(ExtractFileExt(Name));
  Result := (Ext = '.pas') or (Ext = '.pp') or (Ext = '.lpr');
end;

{ Files: a borrow of the caller's list. }
procedure AddFiles(const Path: String; const Files: TStringList);
var
  R: TSearchRec;
  Dir: String;
begin
  if not DirectoryExists(Path) then
  begin
    Files.Add(Path);
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(Path);
  if FindFirst(Dir + '*', faAnyFile, R) = 0 then
    try
      repeat
        if (R.Name = '') or (R.Name[1] = '.') then
          Continue;
        if (R.Attr and faDirectory) <> 0 then
          AddFiles(Dir + R.Name, Files)
        else if IsSource(R.Name) then
          Files.Add(Dir + R.Name);
      until FindNext(R) <> 0;
    finally
      FindClose(R);
    end;
end;

var
  Mode: TVetMode = vmDefault;
  Defines, IncludeDirs, Implicit: TNames;
  Files: TListBox;
  Report: TVetReport;
  Src: TVetSource;
  Module: TPasModule;
  A, Err, RtlDir, CacheDir, Salt, Key: String;
  Typed: Boolean = False;
  Fixing: Boolean = False;
  I, Errors, Warnings, Fatals, From: Integer;
  KeyPaths, StatPaths: TKeyPaths;
  N: Integer;
{ The checks of one file, their findings into Report. }
procedure CheckFile(const Name: String);
begin
  if not VetReadSource(Name, Src, Err) then
  begin
    VetAdd(Report, Name, 1, 1, vsFatal, '', 'bpvet cannot read this file: ' + Err);
    Exit;
  end;
  VetCheckStyle(Src, Report);
  Module := VetParse(Src, Defines, IncludeDirs, Report);
  if Module = nil then
    Exit;
  VetRunRules(Src, Module, Report);
  Module.Release;
  if Typed then
    VetResolve(Src, RtlDir, Defines, IncludeDirs, VetUnitDirs, Implicit, Report);
end;

begin
  if (ParamCount >= 1) and (ParamStr(1) = '--stubkey') then
  begin
    SetLength(KeyPaths, ParamCount - 1);
    for I := 2 to ParamCount do
      KeyPaths[I - 2] := ParamStr(I);
    PrintStubKey(KeyPaths);
    Halt(0);
  end;
  if (ParamCount >= 2) and (ParamStr(1) = '--buildkey') then
  begin
    N := 3;
    while (N <= ParamCount) and (ParamStr(N) <> '--') do
      Inc(N);
    SetLength(KeyPaths, N - 3);
    for I := 3 to N - 1 do
      KeyPaths[I - 3] := ParamStr(I);
    SetLength(StatPaths, 0);
    if N < ParamCount then
      SetLength(StatPaths, ParamCount - N);
    for I := N + 1 to ParamCount do
      StatPaths[I - N - 1] := ParamStr(I);
    PrintBuildKeys(ParamStr(2), KeyPaths, StatPaths);
    Halt(0);
  end;
  Salt := '';
  CacheDir := '';
  Files := TListBox.Own(TStringList.Create);
  Files.Get.Sorted := True;
  Files.Get.Duplicates := dupIgnore;
  I := 1;
  while I <= ParamCount do
  begin
    A := ParamStr(I);
    Inc(I);
    if Copy(A, 1, 1) = '-' then
      Salt := Salt + #0 + A; // the options are a part of every key of the cache
    if A = '--report' then
      Mode := vmReport
    else if A = '--strict' then
      Mode := vmStrict
    else if A = '--typed' then
      Typed := True
    else if A = '--fix' then
    begin
      Fixing := True;
      S17Fix := True;
      CastFix := True;
      StyleFix := True;
    end
    else if (A = '--rtl') and (I <= ParamCount) then
    begin
      RtlDir := ParamStr(I);
      Salt := Salt + #0 + A + #0 + RtlDir;
      Inc(I);
    end
    else if (A = '--cache') and (I <= ParamCount) then
    begin
      CacheDir := ParamStr(I);
      Inc(I);
    end
    else if (A = '--salt') and (I <= ParamCount) then
    begin
      Salt := Salt + #0 + A + #0 + ParamStr(I);
      Inc(I);
    end
    else if (A = '-h') or (A = '--help') then
    begin
      Usage;
      Halt(0);
    end
    else if Copy(A, 1, 2) = '-d' then
      AddTo(Defines, Copy(A, 3, Length(A)))
    else if Copy(A, 1, 3) = '-Fa' then
      AddTo(Implicit, Copy(A, 4, Length(A)))
    else if Copy(A, 1, 3) = '-Fi' then
      AddTo(IncludeDirs, Copy(A, 4, Length(A)))
    else if Copy(A, 1, 3) = '-Fu' then
    begin
      SetLength(VetUnitDirs, Length(VetUnitDirs) + 1);
      VetUnitDirs[High(VetUnitDirs)] := Copy(A, 4, Length(A));
    end
    else if Copy(A, 1, 1) = '-' then
    begin
      WriteLn('bpvet: unknown option ', A);
      Usage;
      Halt(2);
    end
    else
      AddFiles(A, Files.Get);
  end;
  if (Files.Get.Count = 0) or (Typed and (RtlDir = '')) then
  begin
    Usage;
    Halt(2);
  end;

  if Fixing then
    CacheDir := '';
  if CacheDir <> '' then
    VetCacheTargets(Files.Get);
  for I := 0 to Files.Get.Count - 1 do
  begin
    Key := '';
    if CacheDir <> '' then
    begin
      Key := VetCacheKey(Salt, Files.Get[I], IncludeDirs);
      if VetCacheLoad(CacheDir, Key, Report) then
        Continue;
    end;
    From := Length(Report.Findings);
    CheckFile(Files.Get[I]);
    if CacheDir <> '' then
      VetCacheStore(CacheDir, Key, Report, From);
  end;

  Errors := 0;
  Warnings := 0;
  Fatals := 0;
  VetPrint(Report, Mode, Errors, Warnings, Fatals);
  WriteLn(Format('bpvet: %d file(s), %d error(s), %d warning(s), %d fatal', [Files.Get.Count, Errors, Warnings, Fatals]));
  if Fatals > 0 then
    ExitCode := 2
  else if Errors > 0 then
    ExitCode := 1;
end.
