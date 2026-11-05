{ SPDX-License-Identifier: MIT }
{ bpvet --stubkey PATH...: the text the RTL stubs of the typed mode depend on (safe/SPEC.md §25.5). The stubs that
  tools/bpvet/resolver/genstubs.py writes for a set of sources depend only on the identifiers of the sources and on the
  units their uses clauses name, so tools/bp keys its cache of stubs on this text: an edit that adds no identifier keeps
  the stubs. The scan is the one of scan_sources in genstubs.py: comments and string literals are blanked, then every
  identifier is taken in lower case, and every uses clause (up to its semicolon) gives its unit names without an
  "in 'file'" part. The output is the sorted identifiers, one per line, a line "|", and the sorted unit names, one per
  line. A directory is walked for *.pas, *.pp, *.inc, *.lpr and *.dpr.
  bpvet --buildkey SALT TARGET... -- STAT...: both keys of a build of tools/bp in one run, so that a rebuild starts no
  chain of stat, find, cat and sha256sum. }
unit BpvetKey;

{$mode objfpc}{$H+}

interface

uses
  Classes;

type
  TKeyPaths = array of String;

{ The identifiers (lower case) and the units of the uses clauses (lower case, without "in 'file'") of Text, as
  genstubs.py scans them. Idents, Units: borrows of the caller's lists. }
procedure ScanText(const Text: String; Idents, Units: TStringList);

{ Writes the key text of Paths to the standard output. }
procedure PrintStubKey(const Paths: TKeyPaths);

{ Writes the two keys of a build to the standard output, on one line: the key of the RTL stubs and the key of the check.
  Salt is what both depend on besides the files (the version of fpc, the options of the check). The key of the stubs
  takes the key text of Targets and the name, size and time of every file of Stats (of a directory: its *.pas, *.pp
  and *.inc); the key of the check takes the key of the stubs and the paths and texts of the sources of Targets. }
procedure PrintBuildKeys(const Salt: String; const Targets, Stats: TKeyPaths);

implementation

uses
  SysUtils, md5, Safe;

type
  TListBox = specialize TOwned<TStringList>;

function IsWordChar(const C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

{ The text with its comments ({ }, (* *), //) and string literals turned into blanks. A comment or a string with no
  end stays as it is, as the pattern of genstubs.py leaves it. }
function Blanked(const Text: String): String;
var
  I, J, N: SizeInt;
begin
  Result := Text;
  N := Length(Text);
  I := 1;
  while I <= N do
  begin
    J := 0;
    if Text[I] = '{' then
    begin
      J := I + 1;
      while (J <= N) and (Text[J] <> '}') do
        Inc(J);
      if J > N then
        J := 0;
    end
    else if (Text[I] = '(') and (I < N) and (Text[I + 1] = '*') then
    begin
      J := I + 2;
      while (J < N) and not ((Text[J] = '*') and (Text[J + 1] = ')')) do
        Inc(J);
      if J < N then
        Inc(J)
      else
        J := 0;
    end
    else if (Text[I] = '/') and (I < N) and (Text[I + 1] = '/') then
    begin
      J := I + 2;
      while (J <= N) and (Text[J] <> #10) do
        Inc(J);
      Dec(J);
    end
    else if Text[I] = '''' then
    begin
      J := I + 1;
      while J <= N do
        if Text[J] <> '''' then
          Inc(J)
        else if (J < N) and (Text[J + 1] = '''') then
          Inc(J, 2)
        else
          Break;
      if J > N then
        J := 0;
    end;
    if J = 0 then
      Inc(I)
    else
    begin
      while I <= J do
      begin
        Result[I] := ' ';
        Inc(I);
      end;
    end;
  end;
end;

{ A unit name: identifiers joined by dots. }
function IsUnitName(const S: String): Boolean;
var
  I: SizeInt;
  AtStart: Boolean;
begin
  Result := S <> '';
  AtStart := True;
  for I := 1 to Length(S) do
    if AtStart then
    begin
      if not (S[I] in ['A'..'Z', 'a'..'z', '_']) then
        Exit(False);
      AtStart := False;
    end
    else if S[I] = '.' then
      AtStart := True
    else if not IsWordChar(S[I]) then
      Exit(False);
  Result := Result and not AtStart;
end;

{ The position of the word W (lower case) in the lower-case text L at or after From, as a whole word; 0 if none. }
function FindWord(const L, W: String; const From: SizeInt): SizeInt;
var
  P: SizeInt;
begin
  P := From;
  repeat
    Result := Pos(W, Copy(L, P, Length(L)));
    if Result = 0 then
      Exit;
    Result := Result + P - 1;
    if ((Result = 1) or not IsWordChar(L[Result - 1])) and
      ((Result + Length(W) > Length(L)) or not IsWordChar(L[Result + Length(W)])) then
      Exit;
    P := Result + 1;
  until False;
end;

procedure ScanText(const Text: String; Idents, Units: TStringList);
var
  Code, L, Clause, Part: String;
  I, J, N, P, Semi: SizeInt;
begin
  Code := Blanked(Text);
  N := Length(Code);
  I := 1;
  while I <= N do
    if Code[I] in ['A'..'Z', 'a'..'z', '_'] then
    begin
      J := I;
      while (J <= N) and IsWordChar(Code[J]) do
        Inc(J);
      Idents.Add(LowerCase(Copy(Code, I, J - I)));
      I := J;
    end
    else
      Inc(I);
  L := LowerCase(Code);
  P := FindWord(L, 'uses', 1);
  while P > 0 do
  begin
    Semi := Pos(';', Copy(L, P + 4, N));
    if Semi = 0 then
      Break;
    Clause := Copy(Code, P + 4, Semi - 1);
    while Clause <> '' do
    begin
      J := Pos(',', Clause);
      if J = 0 then
        J := Length(Clause) + 1;
      Part := Copy(Clause, 1, J - 1);
      Delete(Clause, 1, J);
      I := FindWord(LowerCase(Part), 'in', 1);
      if I > 0 then
        Part := Copy(Part, 1, I - 1);
      Part := Trim(Part);
      if IsUnitName(Part) then
        Units.Add(LowerCase(Part));
    end;
    P := FindWord(L, 'uses', P + 4 + Semi);
  end;
end;

function IsKeySource(const Name: String): Boolean;
var
  Ext: String;
begin
  Ext := LowerCase(ExtractFileExt(Name));
  Result := (Ext = '.pas') or (Ext = '.pp') or (Ext = '.inc') or (Ext = '.lpr') or (Ext = '.dpr');
end;

{ The sources under Path, in Names: Path itself when it is a source file, else every source of the directory tree. }
procedure ListSources(const Path: String; Names: TStringList);
var
  R: TSearchRec;
  Dir: String;
begin
  if not DirectoryExists(Path) then
  begin
    if FileExists(Path) and IsKeySource(Path) then
      Names.Add(Path);
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(Path);
  if FindFirst(Dir + '*', faAnyFile or faDirectory, R) = 0 then
  try
    repeat
      if (R.Name = '.') or (R.Name = '..') then
        Continue;
      if (R.Attr and faDirectory) <> 0 then
        ListSources(Dir + R.Name, Names)
      else if IsKeySource(R.Name) then
        Names.Add(Dir + R.Name);
    until FindNext(R) <> 0;
  finally
    FindClose(R);
  end;
end;

{ An empty list that keeps its lines sorted, each once. }
function SortedBox: TListBox;
begin
  Result := TListBox.Own(TStringList.Create);
  Result.Get.Sorted := True;
  Result.Get.Duplicates := dupIgnore;
  Result.Get.CaseSensitive := True;
end;

{ The key text of the sources of Paths; with Texts, also the paths and texts of the sources, in the order of their
  paths. }
function KeyText(const Paths: TKeyPaths; const Texts: TStringList): String;
var
  Names, Idents, Units, Text: TListBox;
  I: Integer;
begin
  Names := SortedBox;
  Idents := SortedBox;
  Units := SortedBox;
  Text := TListBox.Own(TStringList.Create);
  for I := 0 to High(Paths) do
    ListSources(Paths[I], Names.Get);
  for I := 0 to Names.Get.Count - 1 do
  begin
    Text.Get.LoadFromFile(Names.Get[I]);
    ScanText(Text.Get.Text, Idents.Get, Units.Get);
    if Texts <> nil then
    begin
      Texts.Add(Names.Get[I]);
      Texts.Add(Text.Get.Text);
    end;
  end;
  Result := '';
  for I := 0 to Idents.Get.Count - 1 do
    Result := Result + Idents.Get[I] + LineEnding;
  Result := Result + '|' + LineEnding;
  for I := 0 to Units.Get.Count - 1 do
    Result := Result + Units.Get[I] + LineEnding;
end;

{ The name, size and time of a file, one line. }
function StatLine(const Name: String; const R: TSearchRec): String;
begin
  Result := Name + ' ' + IntToStr(R.Size) + ' ' + IntToStr(R.Time) + LineEnding;
end;

{ The name, size and time of every file of Paths (of a directory: its *.pas, *.pp and *.inc), sorted. }
function StatText(const Paths: TKeyPaths): String;
var
  Lines: TListBox;
  R: TSearchRec;
  Dir, Ext: String;
  I: Integer;
begin
  Lines := SortedBox;
  for I := 0 to High(Paths) do
    if DirectoryExists(Paths[I]) then
    begin
      Dir := IncludeTrailingPathDelimiter(Paths[I]);
      if FindFirst(Dir + '*', faAnyFile, R) = 0 then
      try
        repeat
          Ext := LowerCase(ExtractFileExt(R.Name));
          if (Ext = '.pas') or (Ext = '.pp') or (Ext = '.inc') then
            Lines.Get.Add(StatLine(Dir + R.Name, R));
        until FindNext(R) <> 0;
      finally
        FindClose(R);
      end;
    end
    else if FindFirst(Paths[I], faAnyFile, R) = 0 then
    try
      Lines.Get.Add(StatLine(Paths[I], R));
    finally
      FindClose(R);
    end;
  Result := '';
  for I := 0 to Lines.Get.Count - 1 do
    Result := Result + Lines.Get[I];
end;

procedure PrintStubKey(const Paths: TKeyPaths);
begin
  Write(KeyText(Paths, nil));
end;

procedure PrintBuildKeys(const Salt: String; const Targets, Stats: TKeyPaths);
var
  Texts: TListBox;
  StubKey, Check: String;
  I: Integer;
begin
  Texts := TListBox.Own(TStringList.Create);
  StubKey := MD5Print(MD5String(Salt + #0 + KeyText(Targets, Texts.Get) + #0 + StatText(Stats)));
  Check := Salt + #0 + StubKey;
  for I := 0 to Texts.Get.Count - 1 do
    Check := Check + #0 + Texts.Get[I];
  WriteLn(StubKey, ' ', MD5Print(MD5String(Check)));
end;

end.
