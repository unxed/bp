{ SPDX-License-Identifier: MIT }
{ The rules of bpvet over the text of a file, before it is parsed (safe/SPEC.md §6, the style of §0):
    S21  the header: a file starts with program/unit/library/package and the name of the file;
    S22  reserved words are written in lower case.
  Both are fixed in place by --fix (StyleFix). }
unit BpvetStyle;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, BpvetCore, Safe;

var
  { --fix of bpvet: S21 writes the header, S22 lowers the reserved words; the file is rewritten and Src changes too }
  StyleFix: Boolean = False;

{ S21: the name of a program or unit has one source, the name of its file (safe/SPEC.md §0).
    Error    the file has no header: program for a file without interface, unit for one with it (--fix inserts
             "program Name;" or "unit Name;" before the first token);
    Error    the name in the header is not the name of the file (letter case aside; --fix writes the name of the file).
    A file whose name is not an identifier (dots allowed, as in unit names) is reported without a fix.
  S22: reserved words in lower case (safe/SPEC.md §0).
    Warning  a reserved word with an upper-case letter (Begin, END); --fix lowers it. string is not checked: it is
             written as the type it names (String). Comments, strings, &escaped identifiers and the bodies of
             asm blocks are skipped. }
procedure VetCheckStyle(var Src: TVetSource; var Report: TVetReport);

implementation

type
  TTok = record
    Row, Col: Integer;  // 1-based
    Text: String;       // '' at the end of the file
    Ident: Boolean;     // an identifier or a reserved word, not escaped with &
  end;

  TScanner = record
    Lines: array of String;
    Row, Col: Integer;  // the next character to read
  end;

  TLinesBox = specialize TOwned<TStringList>;

const
  Reserved: array[0..62] of String = ('and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file', 'finalization',
    'finally', 'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited', 'initialization', 'interface',
    'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'operator', 'or', 'packed', 'procedure',
    'program', 'property', 'raise', 'record', 'repeat', 'resourcestring', 'set', 'shl', 'shr', 'then', 'threadvar',
    'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor');

function IsReserved(const W: String): Boolean;
var
  I: Integer;
  L: String;
begin
  L := LowerCase(W);
  for I := 0 to High(Reserved) do
    if Reserved[I] = L then
      Exit(True);
  Result := False;
end;

function IdentStart(const C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '_'];
end;

function IdentChar(const C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '_', '0'..'9'];
end;

function Cur(const S: TScanner): Char;
begin
  if S.Row > Length(S.Lines) then
    Result := #0
  else if S.Col > Length(S.Lines[S.Row - 1]) then
    Result := #10
  else
    Result := S.Lines[S.Row - 1][S.Col];
end;

function Peek(const S: TScanner): Char;
begin
  if (S.Row > Length(S.Lines)) or (S.Col + 1 > Length(S.Lines[S.Row - 1])) then
    Result := #10
  else
    Result := S.Lines[S.Row - 1][S.Col + 1];
end;

procedure Step(var S: TScanner);
begin
  if S.Row > Length(S.Lines) then
    Exit;
  if S.Col > Length(S.Lines[S.Row - 1]) then
  begin
    Inc(S.Row);
    S.Col := 1;
  end
  else
    Inc(S.Col);
end;

{ Skips blanks and comments (braces, (* *), //; directives are comments here). }
procedure SkipBlank(var S: TScanner);
begin
  while True do
    case Cur(S) of
      #0:
        Exit;
      ' ', #9, #10, #13:
        Step(S);
      '{':
        begin
          while not (Cur(S) in ['}', #0]) do
            Step(S);
          Step(S);
        end;
      '(':
        if Peek(S) = '*' then
        begin
          Step(S);
          Step(S);
          while not ((Cur(S) = #0) or (Cur(S) = '*') and (Peek(S) = ')')) do
            Step(S);
          Step(S);
          Step(S);
        end
        else
          Exit;
      '/':
        if Peek(S) = '/' then
        begin
          Inc(S.Row);
          S.Col := 1;
        end
        else
          Exit;
    else
      Exit;
    end;
end;

function Next(var S: TScanner): TTok;
var
  Line: String;
  Escaped: Boolean;
begin
  SkipBlank(S);
  Result.Row := S.Row;
  Result.Col := S.Col;
  Result.Text := '';
  Result.Ident := False;
  if Cur(S) = #0 then
    Exit;
  Line := S.Lines[S.Row - 1];
  Escaped := (Cur(S) = '&') and IdentStart(Peek(S));
  if Escaped then
    Step(S);
  if IdentStart(Cur(S)) then
  begin
    while (S.Col <= Length(Line)) and IdentChar(Line[S.Col]) do
      Inc(S.Col);
    Result.Text := Copy(Line, Result.Col, S.Col - Result.Col);
    Result.Ident := not Escaped;
  end
  else if Cur(S) = '''' then
  begin
    Step(S);
    while (S.Col <= Length(Line)) and ((Line[S.Col] <> '''') or (S.Col < Length(Line)) and (Line[S.Col + 1] = ''''))
      do
      if Line[S.Col] = '''' then
        Inc(S.Col, 2)
      else
        Inc(S.Col);
    Step(S);
    Result.Text := '''';
  end
  else
  begin
    Result.Text := Cur(S);
    Step(S);
  end;
end;

{ The name of the file without the extension when it is an identifier with dots, else ''. }
function FileModuleName(const FileName: String): String;
var
  I: Integer;
begin
  Result := ChangeFileExt(ExtractFileName(FileName), '');
  if (Result = '') or not IdentStart(Result[1]) or (Result[Length(Result)] = '.') then
    Exit('');
  for I := 2 to Length(Result) do
    if not (IdentChar(Result[I]) or (Result[I] = '.') and (Result[I - 1] <> '.')) then
      Exit('');
end;

procedure Replace(var Line: String; const Col, Len: Integer; const S: String);
begin
  Line := Copy(Line, 1, Col - 1) + S + Copy(Line, Col + Len, MaxInt);
end;

procedure VetCheckStyle(var Src: TVetSource; var Report: TVetReport);
var
  S: TScanner;
  T, First, NameTok, Last: TTok;
  Kind, Name, Want: String;
  Fixed, HasInterface, InAsm: Boolean;
  Lines: TLinesBox;
  I: Integer;
begin
  S.Lines := Copy(Src.Lines);
  S.Row := 1;
  S.Col := 1;
  Fixed := False;
  HasInterface := False;
  InAsm := False;
  Want := FileModuleName(Src.FileName);
  First := Next(S);

  { S22 over every token; the header is checked after the walk, so that the columns of S22 stay those of the file }
  T := First;
  while T.Text <> '' do
  begin
    if T.Ident then
      if InAsm then
        InAsm := LowerCase(T.Text) <> 'end'
      else if IsReserved(T.Text) then
      begin
        if LowerCase(T.Text) = 'interface' then
          HasInterface := True
        else if LowerCase(T.Text) = 'asm' then
          InAsm := True;
        if T.Text <> LowerCase(T.Text) then
        begin
          VetAdd(Report, Src.FileName, T.Row, T.Col, vsWarning, 'S22', Format('the reserved word "%s" is not in lower ' +
            'case; write "%s" (bpvet --fix does it)', [T.Text, LowerCase(T.Text)]));
          if StyleFix then
          begin
            Replace(Src.Lines[T.Row - 1], T.Col, Length(T.Text), LowerCase(T.Text));
            Fixed := True;
          end;
        end;
      end;
    T := Next(S);
  end;

  { S21 }
  Kind := LowerCase(First.Text);
  if First.Ident and ((Kind = 'program') or (Kind = 'unit') or (Kind = 'library') or (Kind = 'package')) then
  begin
    S.Row := First.Row;
    S.Col := First.Col + Length(First.Text);
    NameTok := Next(S);
    Name := NameTok.Text;
    Last := NameTok;
    T := Next(S);
    while T.Text = '.' do
    begin
      T := Next(S);
      Name := Name + '.' + T.Text;
      Last := T;
      T := Next(S);
    end;
    if (Want <> '') and not SameText(Name, Want) then
    begin
      VetAdd(Report, Src.FileName, NameTok.Row, NameTok.Col, vsError, 'S21', Format('the %s is named "%s", its file ' +
        '"%s": the name of a %s is the name of its file; write "%s %s" (bpvet --fix does it)', [Kind, Name,
        ExtractFileName(Src.FileName), Kind, Kind, Want]));
      if StyleFix and (NameTok.Row = Last.Row) then
      begin
        Replace(Src.Lines[NameTok.Row - 1], NameTok.Col, Last.Col + Length(Last.Text) - NameTok.Col, Want);
        Fixed := True;
      end;
    end;
  end
  else if First.Text <> '' then
  begin
    if HasInterface then
      Kind := 'unit'
    else
      Kind := 'program';
    if Want = '' then
      VetAdd(Report, Src.FileName, First.Row, First.Col, vsError, 'S21', Format('the file has no header, and its ' +
        'name "%s" is not an identifier; rename the file and write "%s <the name of the file>;" first',
        [ExtractFileName(Src.FileName), Kind]))
    else
    begin
      VetAdd(Report, Src.FileName, First.Row, First.Col, vsError, 'S21', Format('the file has no header; write ' +
        '"%s %s;" first: the name of a %s is the name of its file (bpvet --fix does it)', [Kind, Want, Kind]));
      if StyleFix then
      begin
        Lines := TLinesBox.Own(TStringList.Create);
        for I := 0 to High(Src.Lines) do
        begin
          if I = First.Row - 1 then
          begin
            Lines.Get.Add(Kind + ' ' + Want + ';');
            Lines.Get.Add('');
          end;
          Lines.Get.Add(Src.Lines[I]);
        end;
        SetLength(Src.Lines, Lines.Get.Count);
        for I := 0 to Lines.Get.Count - 1 do
          Src.Lines[I] := Lines.Get[I];
        Fixed := True;
      end;
    end;
  end;

  if Fixed then
  begin
    Lines := TLinesBox.Own(TStringList.Create);
    for I := 0 to High(Src.Lines) do
      Lines.Get.Add(Src.Lines[I]);
    Lines.Get.SaveToFile(Src.FileName);
  end;
end;

end.
