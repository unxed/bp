{ SPDX-License-Identifier: MIT }
{ bpvet: the linter of Better Pascal for the rules that the compiler cannot check (safe/SPEC.md §6).
  Built by tools/bpvet/build.sh (FPC with fcl-passrc); it reads the sources only, no other unit is needed.

  usage: bpvet [--report|--strict] [-dNAME]... [-FiDIR]... [-FuDIR]... FILE|DIR...
    a directory is walked for *.pas, *.pp, *.lpr (include files are read through the modules that include them);
    -dNAME defines a symbol for conditional compilation, -FiDIR adds an include directory (as for fpc);
    -FuDIR adds a directory where rule S5 looks for the files of used units (their classes);
    the target for conditional compilation is linux, x86_64.
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
  Rules: S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, S15, S16 (bpvetrules.pas). }
program bpvet;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, PasTree, BpvetCore, BpvetRules, Safe;

type
  TListBox = specialize TOwned<TStringList>;
  TNames = array of String;

procedure Usage;
begin
  WriteLn('usage: bpvet [--report|--strict] [-dNAME]... [-FiDIR]... [-FuDIR]... FILE|DIR...');
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
  Defines, IncludeDirs: TNames;
  Files: TListBox;
  Report: TVetReport;
  Src: TVetSource;
  Module: TPasModule;
  A, Err: String;
  I, Errors, Warnings, Fatals: Integer;
begin
  Files := TListBox.Own(TStringList.Create);
  Files.Get.Sorted := True;
  Files.Get.Duplicates := dupIgnore;
  for I := 1 to ParamCount do
  begin
    A := ParamStr(I);
    if A = '--report' then
      Mode := vmReport
    else if A = '--strict' then
      Mode := vmStrict
    else if (A = '-h') or (A = '--help') then
    begin
      Usage;
      Halt(0);
    end
    else if Copy(A, 1, 2) = '-d' then
      AddTo(Defines, Copy(A, 3, Length(A)))
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
  if Files.Get.Count = 0 then
  begin
    Usage;
    Halt(2);
  end;

  for I := 0 to Files.Get.Count - 1 do
  begin
    if not VetReadSource(Files.Get[I], Src, Err) then
    begin
      VetAdd(Report, Files.Get[I], 1, 1, vsFatal, '', 'bpvet cannot read this file: ' + Err);
      Continue;
    end;
    Module := VetParse(Src, Defines, IncludeDirs, Report);
    if Module = nil then
      Continue;
    VetRunRules(Src, Module, Report);
    Module.Release;
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
