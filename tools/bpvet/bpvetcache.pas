{ SPDX-License-Identifier: MIT }
{ The check cache of bpvet, one entry per file (safe/SPEC.md §25.5): with --cache DIR the findings of a file are stored
  under a key of what its check reads, and given again without a check while the key stays the same, so a rebuild after
  an edit of one file of a project checks that file and the files that use it, not all of them. The key of a file takes
  the salt (--salt; tools/bp gives the key of the RTL stubs, which covers the version of fpc, bpvet itself, the options,
  the identifiers of the program and the name, size and time of every file of the unit path), the options of the run,
  and the path and the text of the file, of its include files and of every unit it uses that is one of the targets or
  lies in the directory of the file, through the units and include files these use in turn. A unit found anywhere else
  (the unit path, the stubs) is left to the salt. }
unit BpvetCache;

{$mode objfpc}{$H+}

interface

uses
  Classes, BpvetCore;

{ The targets of the run: a unit that a file uses is looked up among them first. Names: a borrow; it is copied. }
procedure VetCacheTargets(const Names: TStringList);
{ The key of the check of FileName, or '' when the file cannot be read (then it is not cached). }
function VetCacheKey(const Salt, FileName: String; const IncludeDirs: array of String): String;
{ Adds the stored findings of Key to Report; False when there are none. }
function VetCacheLoad(const Dir, Key: String; var Report: TVetReport): Boolean;
{ Stores the findings of Report from the index From on under Key. }
procedure VetCacheStore(const Dir, Key: String; const Report: TVetReport; const From: Integer);

implementation

uses
  SysUtils, md5, BpvetKey, Safe;

type
  TListBox = specialize TOwned<TStringList>;

var
  GTargets: TListBox;  // lower-case unit name = path of a target
  GFacts: TListBox;    // path = the MD5 of its text, a tab, the paths it depends on separated by tabs

function NewList: TListBox;
begin
  Result := TListBox.Own(TStringList.Create);
  Result.Get.NameValueSeparator := #1;
end;

procedure VetCacheTargets(const Names: TStringList);
var
  I: Integer;
begin
  GTargets := NewList;
  for I := 0 to Names.Count - 1 do
    GTargets.Get.Add(LowerCase(ChangeFileExt(ExtractFileName(Names[I]), '')) + #1 + Names[I]);
end;

{ The path of the first of Dir + Name, Dir + Name + '.inc', '.pp', '.pas' that exists, or ''. }
function FindFileIn(const Dir, Name: String): String;
begin
  Result := Dir + Name;
  if FileExists(Result) then
    Exit;
  if ExtractFileExt(Name) = '' then
  begin
    Result := Dir + Name + '.inc';
    if FileExists(Result) then
      Exit;
    Result := Dir + Name + '.pp';
    if FileExists(Result) then
      Exit;
    Result := Dir + Name + '.pas';
    if FileExists(Result) then
      Exit;
  end;
  Result := '';
end;

{ The include file Name of a file in Dir: Dir first, then the include directories, as fpc looks for it. }
function FindInclude(const Dir, Name: String; const IncludeDirs: array of String): String;
var
  I: Integer;
begin
  Result := FindFileIn(Dir, Name);
  for I := 0 to High(IncludeDirs) do
    if Result = '' then
      Result := FindFileIn(IncludeTrailingPathDelimiter(IncludeDirs[I]), Name);
end;

{ The unit Name (lower case) that a file in Dir uses: a target, else a source of Dir; '' when it is neither. }
function FindUnit(const Dir, Name: String): String;
begin
  Result := '';
  if not GTargets.IsEmpty then
    Result := GTargets.Get.Values[Name];
  if Result = '' then
  begin
    Result := Dir + Name + '.pas';
    if not FileExists(Result) then
      Result := Dir + Name + '.pp';
    if not FileExists(Result) then
      Result := '';
  end;
end;

// the names of the include directives of Text ($I NAME, $INCLUDE NAME, in braces), into Names
procedure ScanIncludes(const Text: String; const Names: TStringList);
var
  L, Name: String;
  P, Q, N: SizeInt;
begin
  L := LowerCase(Text);
  N := Length(L);
  P := Pos('{$i', L);
  while P > 0 do
  begin
    Q := P + 3;
    if Copy(L, Q, 6) = 'nclude' then
      Inc(Q, 6);
    if (Q <= N) and (L[Q] in [' ', #9]) then
    begin
      Name := Copy(Text, Q, N);
      Name := Trim(Copy(Name, 1, Pos('}', Name) - 1));
      if (Length(Name) >= 2) and (Name[1] = '''') and (Name[Length(Name)] = '''') then
        Name := Copy(Name, 2, Length(Name) - 2);
      if (Name <> '') and (Name[1] <> '%') then
        Names.Add(Name);
    end;
    P := Pos('{$i', Copy(L, Q, N));
    if P > 0 then
      P := P + Q - 1;
  end;
end;

{ The facts of Path (see GFacts), read and kept on the first call; '' when the file cannot be read. }
function Facts(const Path: String; const IncludeDirs: array of String): String;
var
  Text, Idents, Units, Incs: TListBox;
  Dir, Dep: String;
  I: Integer;
begin
  if GFacts.IsEmpty then
    GFacts := NewList;
  I := GFacts.Get.IndexOfName(Path);
  if I >= 0 then
    Exit(GFacts.Get.ValueFromIndex[I]);
  Text := TListBox.Own(TStringList.Create);
  try
    Text.Get.LoadFromFile(Path);
  except
    on EInOutError do
      Exit('');
    on EFOpenError do
      Exit('');
  end;
  Idents := TListBox.Own(TStringList.Create);
  Units := TListBox.Own(TStringList.Create);
  Incs := TListBox.Own(TStringList.Create);
  ScanText(Text.Get.Text, Idents.Get, Units.Get);
  ScanIncludes(Text.Get.Text, Incs.Get);
  Dir := ExtractFilePath(Path);
  Result := MD5Print(MD5String(Text.Get.Text));
  for I := 0 to Units.Get.Count - 1 do
  begin
    Dep := FindUnit(Dir, Units.Get[I]);
    if (Dep <> '') and (Dep <> Path) then
      Result := Result + #9 + Dep;
  end;
  for I := 0 to Incs.Get.Count - 1 do
  begin
    Dep := FindInclude(Dir, Incs.Get[I], IncludeDirs);
    if Dep <> '' then
      Result := Result + #9 + Dep;
  end;
  GFacts.Get.Add(Path + #1 + Result);
end;

function VetCacheKey(const Salt, FileName: String; const IncludeDirs: array of String): String;
var
  Todo, Seen, Lines: TListBox;
  Path, F, Text: String;
  P: SizeInt;
begin
  Todo := TListBox.Own(TStringList.Create);
  Seen := TListBox.Own(TStringList.Create);
  Seen.Get.Sorted := True;
  Lines := TListBox.Own(TStringList.Create);
  Lines.Get.Sorted := True;
  Todo.Get.Add(FileName);
  while Todo.Get.Count > 0 do
  begin
    Path := Todo.Get[Todo.Get.Count - 1];
    Todo.Get.Delete(Todo.Get.Count - 1);
    if Seen.Get.IndexOf(Path) >= 0 then
      Continue;
    Seen.Get.Add(Path);
    F := Facts(Path, IncludeDirs);
    if F = '' then
    begin
      if Path = FileName then
        Exit('');
      Continue;
    end;
    P := Pos(#9, F);
    if P = 0 then
      P := Length(F) + 1;
    Lines.Get.Add(Path + #9 + Copy(F, 1, P - 1));
    Delete(F, 1, P);
    while F <> '' do
    begin
      P := Pos(#9, F);
      if P = 0 then
        P := Length(F) + 1;
      Todo.Get.Add(Copy(F, 1, P - 1));
      Delete(F, 1, P);
    end;
  end;
  Text := Salt + #0 + FileName + #0 + Lines.Get.Text;
  Result := MD5Print(MD5String(Text));
end;

function SeverityOf(const N: Integer; out S: TVetSeverity): Boolean;
var
  V: TVetSeverity;
begin
  for V := Low(TVetSeverity) to High(TVetSeverity) do
    if Ord(V) = N then
    begin
      S := V;
      Exit(True);
    end;
  Result := False;
end;

{ The fields of a line of the cache, split at the tabs, into Parts. }
procedure SplitFields(const Line: String; const Parts: TStringList);
var
  Rest: String;
  P: SizeInt;
begin
  Parts.Clear;
  Rest := Line;
  P := Pos(#9, Rest);
  while P > 0 do
  begin
    Parts.Add(Copy(Rest, 1, P - 1));
    Delete(Rest, 1, P);
    P := Pos(#9, Rest);
  end;
  Parts.Add(Rest);
end;

function VetCacheLoad(const Dir, Key: String; var Report: TVetReport): Boolean;
var
  Lines, Parts: TListBox;
  Sev: TVetSeverity;
  I: Integer;
begin
  Result := False;
  if (Key = '') or not FileExists(Dir + PathDelim + Key) then
    Exit;
  Lines := TListBox.Own(TStringList.Create);
  try
    Lines.Get.LoadFromFile(Dir + PathDelim + Key);
  except
    on EInOutError do
      Exit;
    on EFOpenError do
      Exit;
  end;
  if (Lines.Get.Count = 0) or (Lines.Get[0] <> 'bpvet-cache 1') then
    Exit;
  Parts := TListBox.Own(TStringList.Create);
  for I := 1 to Lines.Get.Count - 1 do
  begin
    SplitFields(Lines.Get[I], Parts.Get);
    if (Parts.Get.Count <> 6) or not SeverityOf(StrToIntDef(Parts.Get[2], -1), Sev) then
      Exit;
  end;
  for I := 1 to Lines.Get.Count - 1 do
  begin
    SplitFields(Lines.Get[I], Parts.Get);
    SeverityOf(StrToIntDef(Parts.Get[2], -1), Sev);
    VetAdd(Report, Parts.Get[4], StrToIntDef(Parts.Get[0], 1), StrToIntDef(Parts.Get[1], 1), Sev, Parts.Get[3],
      Parts.Get[5]);
  end;
  Result := True;
end;

{ S without tabs and line breaks: a field of a line of the cache. }
function Field(const S: String): String;
begin
  Result := StringReplace(StringReplace(StringReplace(S, #9, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]), #13,
    ' ', [rfReplaceAll]);
end;

procedure VetCacheStore(const Dir, Key: String; const Report: TVetReport; const From: Integer);
var
  Lines: TListBox;
  F: TVetFinding;
  Tmp: String;
  I: Integer;
begin
  if Key = '' then
    Exit;
  Lines := TListBox.Own(TStringList.Create);
  Lines.Get.Add('bpvet-cache 1');
  for I := From to High(Report.Findings) do
  begin
    F := Report.Findings[I];
    Lines.Get.Add(IntToStr(F.Row) + #9 + IntToStr(F.Col) + #9 + IntToStr(Ord(F.Severity)) + #9 + Field(F.Rule) + #9 +
      Field(F.FileName) + #9 + Field(F.Msg));
  end;
  // written aside and renamed, so a build running at the same time reads a whole entry or none
  Tmp := Dir + PathDelim + Key + '.' + IntToStr(GetProcessID);
  try
    ForceDirectories(Dir);
    Lines.Get.SaveToFile(Tmp);
    if not RenameFile(Tmp, Dir + PathDelim + Key) then
      DeleteFile(Tmp);
  except
    on EInOutError do
      DeleteFile(Tmp);
    on EFCreateError do
      DeleteFile(Tmp);
  end;
end;

end.
