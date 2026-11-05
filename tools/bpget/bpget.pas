{ SPDX-License-Identifier: MIT }
{ bpget: the dependencies of a Better Pascal program (safe/SPEC.md §15), called by tools/bp:
    bpget get DIR CACHE      resolves the require lines of DIR/deps.txt (MVS) and writes DIR/deps.lock
    bpget vendor DIR CACHE   copies the modules of DIR/deps.lock into DIR/vendor/<path>/
    bpget paths DIR CACHE    prints the unit directories of the modules of DIR/deps.lock, one per line
  Git is the transport, the registry and the integrity check. A module path host/owner/repo names the repository
  https://host/owner/repo (a path that starts with / or file:// is a local repository), a version is a tag vX.Y.Z,
  and deps.lock records the commit of each selected version. Each repository is mirrored once into
  CACHE/mod/<path>.git; a selected version is extracted read-only into CACHE/mod/<path>@<version>/ (git archive, never
  a checkout), with the commit in CACHE/mod/<path>@<version>.commit. }
program bpget;

{$mode objfpc}{$H+}

// UNSAFE: BP goes first for the thread manager (SPEC §14); SysUtils, Classes and Process after it shadow it, and the
// program does not free objects by hand (no FreeAndNil)
uses
  BP, SysUtils, Classes, Process;

type
  TNames = specialize TArray<String>;

  { A require line of deps.txt, and a node of the requirement graph. }
  TReq = record
    Path, Version: String;
  end;
  TReqs = specialize TArray<TReq>;

  { A mirror line: another git URL with the same content as the repository of Path. }
  TMirror = record
    Path, Url: String;
  end;
  TMirrors = specialize TArray<TMirror>;

  { A deps.txt. Safe (the version of the rules of SPEC) is read and kept, not acted on yet. }
  TDeps = record
    Module, Safe: String;
    Requires: TReqs;
    Mirrors: TMirrors;
    Dirs: TNames;
  end;

  { A line of deps.lock (and of vendor/modules.txt): a selected module. }
  TLocked = record
    Path, Version, Commit: String;
  end;
  TLock = specialize TArray<TLocked>;

  { A repository fetched in this run, and the URL it came from. }
  TRepo = record
    Path, Url: String;
  end;
  TRepos = specialize TArray<TRepo>;

  { What one run knows: the cache, the mirror lines read so far, the repositories already fetched. }
  TContext = record
    Cache: String;
    Mirrors: TMirrors;
    Repos: TRepos;
  end;

  TSemver = record
    Major, Minor, Patch: Integer;
  end;

  EBpGet = class(Exception);

  TLines = specialize TOwned<TStringList>;

{ Fails the run with a message for the user. }
procedure Fail(const Msg: String);
begin
  raise EBpGet.Create(Msg);
end;

{ The words of a line of deps.txt or deps.lock: the comment (from //) dropped, split on spaces and tabs. }
function Fields(const Line: String): TNames;
var
  S, W: String;
  I, P: Integer;
begin
  Result := nil;
  S := Line;
  P := Pos('//', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  W := '';
  for I := 1 to Length(S) do
    if (S[I] = ' ') or (S[I] = #9) or (S[I] = #13) then
    begin
      if W <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := W;
        W := '';
      end;
    end
    else
      W := W + S[I];
  if W <> '' then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := W;
  end;
end;

{ The lines of a text. }
function TextLines(const Text: String): TNames;
var
  L: TLines;
  I: Integer;
begin
  Result := nil;
  L := TLines.Own(TStringList.Create);
  L.Get.Text := Text;
  SetLength(Result, L.Get.Count);
  for I := 0 to L.Get.Count - 1 do
    Result[I] := L.Get[I];
end;

function ReadText(const FileName: String): String;
var
  L: TLines;
begin
  L := TLines.Own(TStringList.Create);
  L.Get.LoadFromFile(FileName);
  Result := L.Get.Text;
end;

procedure WriteText(const FileName, Text: String);
var
  L: TLines;
begin
  L := TLines.Own(TStringList.Create);
  L.Get.Text := Text;
  L.Get.SaveToFile(FileName);
end;

function TryVersion(const V: String; out S: TSemver): Boolean;
var
  F: TNames;
begin
  S := Default(TSemver);
  Result := False;
  if (Length(V) < 6) or (V[1] <> 'v') then
    Exit;
  F := TextLines(StringReplace(Copy(V, 2, Length(V)), '.', LineEnding, [rfReplaceAll]));
  if Length(F) <> 3 then
    Exit;
  Result := TryStrToInt(F[0], S.Major) and TryStrToInt(F[1], S.Minor) and TryStrToInt(F[2], S.Patch)
    and (S.Major >= 0) and (S.Minor >= 0) and (S.Patch >= 0);
end;

{ True when version A is greater than version B (numeric compare of X.Y.Z). }
function Greater(const A, B: String): Boolean;
var
  X, Y: TSemver;
begin
  if not TryVersion(A, X) or not TryVersion(B, Y) then
    Fail('not a version vX.Y.Z: ' + A + ' or ' + B);
  if X.Major <> Y.Major then
    Result := X.Major > Y.Major
  else if X.Minor <> Y.Minor then
    Result := X.Minor > Y.Minor
  else
    Result := X.Patch > Y.Patch;
end;

{ A module path without the scheme of a local repository: the part of a cache or vendor directory. }
function PathPart(const Path: String): String;
begin
  Result := Path;
  if Copy(Result, 1, 7) = 'file://' then
    Result := Copy(Result, 8, Length(Result));
  while Copy(Result, 1, 1) = '/' do
    Result := Copy(Result, 2, Length(Result));
end;

{ A module path that cannot name a directory outside the cache or vendor/ (no .. and no empty part). }
procedure CheckPath(const Path, Where: String);
var
  P: String;
begin
  P := '/' + PathPart(Path) + '/';
  if (PathPart(Path) = '') or (Pos('/../', P) > 0) or (Pos('/./', P) > 0) or (Pos('//', P) > 0) then
    Fail(Where + ': not a module path: ' + Path);
end;

{ Reads the text of a deps.txt; Where names it in the messages. }
function ParseDeps(const Text, Where: String): TDeps;
var
  Lines, F: TNames;
  I, J: Integer;
  V: TSemver;
  Ln: String;
begin
  Result := Default(TDeps);
  Lines := TextLines(Text);
  for I := 0 to High(Lines) do
  begin
    F := Fields(Lines[I]);
    if Length(F) = 0 then
      Continue;
    Ln := Format('%s:%d', [Where, I + 1]);
    if (F[0] = 'module') and (Length(F) = 2) then
      Result.Module := F[1]
    else if (F[0] = 'safe') and (Length(F) = 2) then
      Result.Safe := F[1]
    else if (F[0] = 'require') and (Length(F) = 3) then
    begin
      CheckPath(F[1], Ln);
      if not TryVersion(F[2], V) then
        Fail(Ln + ': not a version vX.Y.Z: ' + F[2]);
      SetLength(Result.Requires, Length(Result.Requires) + 1);
      Result.Requires[High(Result.Requires)].Path := F[1];
      Result.Requires[High(Result.Requires)].Version := F[2];
    end
    else if (F[0] = 'mirror') and (Length(F) = 3) then
    begin
      SetLength(Result.Mirrors, Length(Result.Mirrors) + 1);
      Result.Mirrors[High(Result.Mirrors)].Path := F[1];
      Result.Mirrors[High(Result.Mirrors)].Url := F[2];
    end
    else if (F[0] = 'dirs') and (Length(F) >= 2) then
    begin
      SetLength(Result.Dirs, Length(F) - 1);
      for J := 1 to High(F) do
      begin
        CheckPath('x/' + F[J], Ln);
        Result.Dirs[J - 1] := F[J];
      end;
    end
    else
      Fail(Ln + ': expected module, safe, require, mirror or dirs: ' + Lines[I]);
  end;
end;

{ Reads deps.lock or vendor/modules.txt; a missing file is an empty lock. }
function ReadLock(const FileName: String): TLock;
var
  Lines, F: TNames;
  I: Integer;
begin
  Result := nil;
  if not FileExists(FileName) then
    Exit;
  Lines := TextLines(ReadText(FileName));
  for I := 0 to High(Lines) do
  begin
    F := Fields(Lines[I]);
    if Length(F) = 0 then
      Continue;
    if Length(F) <> 3 then
      Fail(Format('%s:%d: expected "path version commit": %s', [FileName, I + 1, Lines[I]]));
    CheckPath(F[0], FileName);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Path := F[0];
    Result[High(Result)].Version := F[1];
    Result[High(Result)].Commit := F[2];
  end;
end;

function LockText(const Lock: TLock): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Lock) do
    Result := Result + Lock[I].Path + ' ' + Lock[I].Version + ' ' + Lock[I].Commit + LineEnding;
end;

{ The index of the line of Path in Lock, or -1. }
function Find(const Lock: TLock; const Path: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Lock) do
    if Lock[I].Path = Path then
      Exit(I);
end;

{ Runs a program and returns whether it exited with 0; Output gets its standard output and error. }
function Run(const Exe: String; const Args: array of String; out Output: String): Boolean;
begin
  Result := RunCommand(Exe, Args, Output, [poStderrToOutPut]);
end;

{ Runs a program that must succeed. }
procedure Must(const Exe: String; const Args: array of AnsiString);
var
  Output: String;
begin
  if not Run(Exe, Args, Output) then
    Fail(Exe + ' ' + Args[0] + ' failed:' + LineEnding + Trim(Output));
end;

function MirrorDir(const Ctx: TContext; const Path: String): String;
begin
  Result := Ctx.Cache + '/mod/' + PathPart(Path) + '.git';
end;

{ The directory of an extracted version in the cache. }
function VersionDir(const Ctx: TContext; const Path, Version: String): String;
begin
  Result := Ctx.Cache + '/mod/' + PathPart(Path) + '@' + Version;
end;

{ The URLs of a module, in the order they are tried: the path itself, the same with .git, the mirror lines. }
function Urls(const Ctx: TContext; const Path: String): TNames;
var
  I: Integer;
begin
  Result := nil;
  if (Copy(Path, 1, 1) = '/') or (Copy(Path, 1, 7) = 'file://') then
  begin
    SetLength(Result, 1);
    Result[0] := Path;
  end
  else
  begin
    SetLength(Result, 2);
    Result[0] := 'https://' + Path;
    Result[1] := 'https://' + Path + '.git';
  end;
  for I := 0 to High(Ctx.Mirrors) do
    if Ctx.Mirrors[I].Path = Path then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Ctx.Mirrors[I].Url;
    end;
end;

{ Mirrors the repository of Path into the cache (git clone --mirror the first time, git fetch later), once per run.
  When no URL answers and a mirror is in the cache, the run goes on with what the mirror has. }
procedure Fetch(var Ctx: TContext; const Path: String);
var
  U: TNames;
  I: Integer;
  M, Output, Errors: String;
begin
  for I := 0 to High(Ctx.Repos) do
    if Ctx.Repos[I].Path = Path then
      Exit;
  M := MirrorDir(Ctx, Path);
  U := Urls(Ctx, Path);
  Errors := '';
  SetLength(Ctx.Repos, Length(Ctx.Repos) + 1);
  Ctx.Repos[High(Ctx.Repos)].Path := Path;
  for I := 0 to High(U) do
  begin
    if DirectoryExists(M) then
    begin
      if Run('git', ['--git-dir=' + M, 'fetch', '--quiet', '--prune', '--force', U[I],
          '+refs/heads/*:refs/heads/*', '+refs/tags/*:refs/tags/*'], Output) then
      begin
        Ctx.Repos[High(Ctx.Repos)].Url := U[I];
        Exit;
      end;
    end
    else
    begin
      Must('mkdir', ['-p', ExtractFileDir(M)]);
      if Run('git', ['clone', '--quiet', '--mirror', U[I], M + '.tmp'], Output) then
      begin
        Must('mv', [M + '.tmp', M]);
        Ctx.Repos[High(Ctx.Repos)].Url := U[I];
        Exit;
      end;
      Must('rm', ['-rf', M + '.tmp']);
    end;
    Errors := Errors + LineEnding + '  ' + U[I] + ': ' + Trim(Output);
  end;
  if DirectoryExists(M) then
  begin
    WriteLn(StdErr, 'bp: ', Path, ': no URL answered, the mirror in the cache is used:', Errors);
    Ctx.Repos[High(Ctx.Repos)].Url := M;
  end
  else
    Fail(Path + ': no URL answered:' + Errors);
end;

{ The URL the repository of Path was fetched from in this run. }
function RepoUrl(const Ctx: TContext; const Path: String): String;
var
  I: Integer;
begin
  Result := MirrorDir(Ctx, Path);
  for I := 0 to High(Ctx.Repos) do
    if Ctx.Repos[I].Path = Path then
      Result := Ctx.Repos[I].Url;
end;

{ The commit of the tag Version in the mirror of Path. }
function TagCommit(const Ctx: TContext; const Path, Version: String): String;
var
  Output: String;
begin
  if not Run('git', ['--git-dir=' + MirrorDir(Ctx, Path), 'rev-parse', '--verify', '--quiet',
      'refs/tags/' + Version + '^{commit}'], Output) then
    Fail(Path + ': no tag ' + Version);
  Result := Trim(Output);
end;

{ Makes sure the mirror of Path has Commit: fetched when it does not. }
procedure Ensure(var Ctx: TContext; const Path, Commit: String);
var
  Output: String;
begin
  if not DirectoryExists(MirrorDir(Ctx, Path))
      or not Run('git', ['--git-dir=' + MirrorDir(Ctx, Path), 'cat-file', '-e', Commit + '^{commit}'], Output) then
    Fetch(Ctx, Path);
  if not Run('git', ['--git-dir=' + MirrorDir(Ctx, Path), 'cat-file', '-e', Commit + '^{commit}'], Output) then
    Fail(Path + ': the commit ' + Commit + ' of deps.lock is not in the repository');
end;

{ The deps.txt of Path at Commit; a module without one has no dependencies. }
function DepsAt(const Ctx: TContext; const Path, Commit: String): TDeps;
var
  Output: String;
begin
  Result := Default(TDeps);
  if not Run('git', ['--git-dir=' + MirrorDir(Ctx, Path), 'cat-file', '-e', Commit + ':deps.txt'], Output) then
    Exit;
  if not Run('git', ['--git-dir=' + MirrorDir(Ctx, Path), 'show', Commit + ':deps.txt'], Output) then
    Fail(Path + ': git show ' + Commit + ':deps.txt failed: ' + Trim(Output));
  Result := ParseDeps(Output, Path + '@' + Commit + ':deps.txt');
end;

{ Extracts Commit of the mirror of Path into Target (git archive | tar -x, through a temporary directory). }
procedure Unpack(const Ctx: TContext; const Path, Commit, Target: String);
begin
  Must('rm', ['-rf', Target + '.tmp', Target + '.tar']);
  Must('mkdir', ['-p', Target + '.tmp']);
  Must('git', ['--git-dir=' + MirrorDir(Ctx, Path), 'archive', '--format=tar', '-o', Target + '.tar', Commit]);
  Must('tar', ['-xf', Target + '.tar', '-C', Target + '.tmp']);
  Must('rm', ['-rf', Target, Target + '.tar']);
  Must('mv', [Target + '.tmp', Target]);
end;

{ True when the version is in the cache with this commit. }
function Cached(const Ctx: TContext; const M: TLocked): Boolean;
var
  D: String;
begin
  D := VersionDir(Ctx, M.Path, M.Version);
  Result := DirectoryExists(D) and FileExists(D + '.commit') and (Trim(ReadText(D + '.commit')) = M.Commit);
end;

{ Extracts a selected version into the cache, read-only, unless it is there already. }
procedure Extract(var Ctx: TContext; const M: TLocked);
var
  D: String;
begin
  if Cached(Ctx, M) then
    Exit;
  Ensure(Ctx, M.Path, M.Commit);
  D := VersionDir(Ctx, M.Path, M.Version);
  if DirectoryExists(D) then
    Must('chmod', ['-R', 'u+w', D]);
  Unpack(Ctx, M.Path, M.Commit, D);
  Must('find', [D, '-type', 'f', '-exec', 'chmod', 'a-w', '{}', '+']);
  WriteText(D + '.commit', M.Commit);
end;

{ MVS: walks the requirement graph from the require lines of the application; the selected version of each module
  is the greatest of the versions required by the modules reached. The result is sorted by path. }
function Resolve(var Ctx: TContext; const App: TDeps): TLock;
var
  Queue: TReqs;
  Seen: TNames;
  R: TReq;
  D: TDeps;
  I, J, K: Integer;
  Commit: String;
  Known: Boolean;
  T: TLocked;
begin
  Result := nil;
  Queue := Copy(App.Requires);
  Seen := nil;
  I := 0;
  while I < Length(Queue) do
  begin
    R := Queue[I];
    Inc(I);
    Known := False;
    for J := 0 to High(Seen) do
      if Seen[J] = R.Path + '@' + R.Version then
        Known := True;
    if Known then
      Continue;
    SetLength(Seen, Length(Seen) + 1);
    Seen[High(Seen)] := R.Path + '@' + R.Version;
    Fetch(Ctx, R.Path);
    Commit := TagCommit(Ctx, R.Path, R.Version);
    D := DepsAt(Ctx, R.Path, Commit);
    if (D.Module <> '') and (D.Module <> R.Path) then
      Fail(R.Path + ' ' + R.Version + ': its deps.txt says module ' + D.Module);
    for J := 0 to High(D.Mirrors) do
    begin
      SetLength(Ctx.Mirrors, Length(Ctx.Mirrors) + 1);
      Ctx.Mirrors[High(Ctx.Mirrors)].Path := D.Mirrors[J].Path;
      Ctx.Mirrors[High(Ctx.Mirrors)].Url := D.Mirrors[J].Url;
    end;
    for J := 0 to High(D.Requires) do
    begin
      SetLength(Queue, Length(Queue) + 1);
      Queue[High(Queue)].Path := D.Requires[J].Path;
      Queue[High(Queue)].Version := D.Requires[J].Version;
    end;
    K := Find(Result, R.Path);
    if K < 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      K := High(Result);
    end
    else if not Greater(R.Version, Result[K].Version) then
      Continue;
    Result[K].Path := R.Path;
    Result[K].Version := R.Version;
    Result[K].Commit := Commit;
  end;
  for I := 1 to High(Result) do
  begin
    T := Result[I];
    J := I - 1;
    while (J >= 0) and (Result[J].Path > T.Path) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;
    Result[J + 1] := T;
  end;
end;

function ReadApp(const Dir: String): TDeps;
begin
  if not FileExists(Dir + '/deps.txt') then
    Fail(Dir + '/deps.txt: no such file');
  Result := ParseDeps(ReadText(Dir + '/deps.txt'), Dir + '/deps.txt');
end;

{ bp get: resolves, checks the commits against deps.lock, extracts the selected versions, writes deps.lock. }
procedure Get(var Ctx: TContext; const Dir: String);
var
  App: TDeps;
  List, Old: TLock;
  I, K: Integer;
  Url: String;
begin
  App := ReadApp(Dir);
  Ctx.Mirrors := Copy(App.Mirrors);
  List := Resolve(Ctx, App);
  Old := ReadLock(Dir + '/deps.lock');
  for I := 0 to High(List) do
  begin
    K := Find(Old, List[I].Path);
    if (K >= 0) and (Old[K].Version = List[I].Version) and (Old[K].Commit <> List[I].Commit) then
      Fail(Format('%s %s: deps.lock records the commit %s, the tag now points to %s: the tag moved or the ' +
        'repository was replaced; delete the line from deps.lock to accept the new content',
        [List[I].Path, List[I].Version, Old[K].Commit, List[I].Commit]));
  end;
  for I := 0 to High(List) do
  begin
    if Cached(Ctx, List[I]) then
      Url := 'cached'
    else
    begin
      Extract(Ctx, List[I]);
      Url := 'from ' + RepoUrl(Ctx, List[I].Path);
    end;
    WriteLn(List[I].Path, ' ', List[I].Version, ' ', List[I].Commit, ' (', Url, ')');
  end;
  if LockText(List) <> LockText(Old) then
    WriteText(Dir + '/deps.lock', LockText(List));
end;

{ The directory of a vendored module. }
function VendorDir(const Dir, Path: String): String;
begin
  Result := Dir + '/vendor/' + PathPart(Path);
end;

{ bp vendor: the modules of deps.lock into vendor/<path>/, listed in vendor/modules.txt; the others are removed. }
procedure Vendor(var Ctx: TContext; const Dir: String);
var
  Lock, Old: TLock;
  I, K: Integer;
  D: String;
begin
  if not FileExists(Dir + '/deps.lock') then
    Fail(Dir + '/deps.lock: no such file; run bp get first');
  Lock := ReadLock(Dir + '/deps.lock');
  Old := ReadLock(Dir + '/vendor/modules.txt');
  for I := 0 to High(Old) do
    if Find(Lock, Old[I].Path) < 0 then
    begin
      D := VendorDir(Dir, Old[I].Path);
      Must('rm', ['-rf', D]);
      D := ExtractFileDir(D);
      while (Length(D) > Length(Dir + '/vendor')) and RemoveDir(D) do
        D := ExtractFileDir(D);
      WriteLn(Old[I].Path, ' ', Old[I].Version, ' (removed)');
    end;
  for I := 0 to High(Lock) do
  begin
    K := Find(Old, Lock[I].Path);
    D := VendorDir(Dir, Lock[I].Path);
    if (K >= 0) and (Old[K].Version = Lock[I].Version) and (Old[K].Commit = Lock[I].Commit)
        and DirectoryExists(D) then
      WriteLn(Lock[I].Path, ' ', Lock[I].Version, ' ', Lock[I].Commit, ' (kept)')
    else
    begin
      Ensure(Ctx, Lock[I].Path, Lock[I].Commit);
      Must('mkdir', ['-p', ExtractFileDir(D)]);
      Unpack(Ctx, Lock[I].Path, Lock[I].Commit, D);
      WriteLn(Lock[I].Path, ' ', Lock[I].Version, ' ', Lock[I].Commit, ' (vendored)');
    end;
  end;
  WriteText(Dir + '/vendor/modules.txt', LockText(Lock));
end;

{ bp build, bp fix: the unit and include directories of the modules of deps.lock, from vendor/ when a module is
  there, else from the cache (fetched and extracted when missing). }
procedure Paths(var Ctx: TContext; const Dir: String);
var
  Lock, Vendored: TLock;
  Mods: TDeps;
  I, J, K: Integer;
  M, D: String;
begin
  Lock := ReadLock(Dir + '/deps.lock');
  Vendored := ReadLock(Dir + '/vendor/modules.txt');
  for I := 0 to High(Lock) do
  begin
    M := VendorDir(Dir, Lock[I].Path);
    K := Find(Vendored, Lock[I].Path);
    if DirectoryExists(M) then
    begin
      if (K < 0) or (Vendored[K].Version <> Lock[I].Version) or (Vendored[K].Commit <> Lock[I].Commit) then
        Fail(Lock[I].Path + ': vendor/ does not match deps.lock; run bp vendor');
    end
    else
    begin
      Extract(Ctx, Lock[I]);
      M := VersionDir(Ctx, Lock[I].Path, Lock[I].Version);
    end;
    Mods := Default(TDeps);
    if FileExists(M + '/deps.txt') then
      Mods := ParseDeps(ReadText(M + '/deps.txt'), M + '/deps.txt');
    if Length(Mods.Dirs) = 0 then
    begin
      SetLength(Mods.Dirs, 2);
      Mods.Dirs[0] := '.';
      Mods.Dirs[1] := 'src';
    end;
    for J := 0 to High(Mods.Dirs) do
    begin
      if Mods.Dirs[J] = '.' then
        D := M
      else
        D := M + '/' + Mods.Dirs[J];
      if DirectoryExists(D) then
        WriteLn(D);
    end;
  end;
end;

procedure Main;
var
  Ctx: TContext;
  Cmd, Dir: String;
begin
  if ParamCount <> 3 then
    Fail('usage: bpget get|vendor|paths DIR CACHE');
  Cmd := ParamStr(1);
  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(ParamStr(2)));
  Ctx := Default(TContext);
  Ctx.Cache := ExcludeTrailingPathDelimiter(ExpandFileName(ParamStr(3)));
  if Cmd = 'get' then
    Get(Ctx, Dir)
  else if Cmd = 'vendor' then
    Vendor(Ctx, Dir)
  else if Cmd = 'paths' then
    Paths(Ctx, Dir)
  else
    Fail('usage: bpget get|vendor|paths DIR CACHE');
end;

begin
  try
    Main;
  except
    on E: EBpGet do
    begin
      WriteLn(StdErr, 'bp: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
