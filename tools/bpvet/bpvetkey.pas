{ SPDX-License-Identifier: MIT }
{ bpvet --stubkey PATH...: the text the RTL stubs of the typed mode depend on (safe/SPEC.md §25.5). The stubs that
  tools/bpvet/resolver/genstubs.py writes for a set of sources depend only on the identifiers of the sources and on the
  units their uses clauses name, so tools/bp keys its cache of stubs on this text: an edit that adds no identifier keeps
  the stubs. The scan is the one of scan_sources in genstubs.py: comments and string literals are blanked, then every
  identifier is taken in lower case, and every uses clause (up to its semicolon) gives its unit names without an
  "in 'file'" part. The output is the sorted identifiers, one per line, a line "|", and the sorted unit names, one per
  line. A directory is walked for *.pas, *.pp, *.inc, *.lpr and *.dpr. }
unit BpvetKey;

{$mode objfpc}{$H+}

interface

type
  TKeyPaths = array of String;

{ Writes the key text of Paths to the standard output. }
procedure PrintStubKey(const Paths: TKeyPaths);

implementation

uses
  SysUtils, Classes, Safe;

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

procedure ScanFile(const Name: String; Idents, Units: TStringList);
var
  Text: TListBox;
begin
  Text := TListBox.Own(TStringList.Create);
  Text.Get.LoadFromFile(Name);
  ScanText(Text.Get.Text, Idents, Units);
end;

procedure ScanPath(const Path: String; Idents, Units: TStringList);
var
  R: TSearchRec;
  Dir: String;
begin
  if not DirectoryExists(Path) then
  begin
    if FileExists(Path) and IsKeySource(Path) then
      ScanFile(Path, Idents, Units);
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(Path);
  if FindFirst(Dir + '*', faAnyFile or faDirectory, R) = 0 then
  try
    repeat
      if (R.Name = '.') or (R.Name = '..') then
        Continue;
      if (R.Attr and faDirectory) <> 0 then
        ScanPath(Dir + R.Name, Idents, Units)
      else if IsKeySource(R.Name) then
        ScanFile(Dir + R.Name, Idents, Units);
    until FindNext(R) <> 0;
  finally
    FindClose(R);
  end;
end;

procedure PrintStubKey(const Paths: TKeyPaths);
var
  Idents, Units: TListBox;
  I: Integer;
begin
  Idents := TListBox.Own(TStringList.Create);
  Units := TListBox.Own(TStringList.Create);
  Idents.Get.Sorted := True;
  Idents.Get.Duplicates := dupIgnore;
  Idents.Get.CaseSensitive := True;
  Units.Get.Sorted := True;
  Units.Get.Duplicates := dupIgnore;
  Units.Get.CaseSensitive := True;
  for I := 0 to High(Paths) do
    ScanPath(Paths[I], Idents.Get, Units.Get);
  for I := 0 to Idents.Get.Count - 1 do
    WriteLn(Idents.Get[I]);
  WriteLn('|');
  for I := 0 to Units.Get.Count - 1 do
    WriteLn(Units.Get[I]);
end;

end.
