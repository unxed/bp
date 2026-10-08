{ The test of UTF8Everywhere. Note that the unit is not in uses:
  -FaUTF8Everywhere from utf8.cfg inserts it. Exit code 0 means all checks passed. }
program test_utf8;

uses
  SysUtils, Classes;

var
  Failed: Integer = 0;

procedure Check(Ok: Boolean; const What: string);
begin
  if Ok then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

var
  S, Ch, Name, Line: string;
  U: UnicodeString;
  Parts: TStringList;
  F: Text;
begin
  S := 'привет';
  Check(DefaultSystemCodePage = CP_UTF8, 'DefaultSystemCodePage = CP_UTF8');
  Check(StringCodePage(S + IntToStr(1)) = CP_UTF8, 'a string from an expression is UTF-8');
  Check(Length(S) = 12, 'Length in bytes: 12');
  Check(CPLength(S) = 6, 'CPLength in characters: 6');
  Check(Pos('ве', S) = 7, 'Pos in bytes: 7');
  Check(Copy(S, Pos('ве', S), MaxInt) = 'вет', 'Copy from the Pos position');

  U := S;
  Check(Length(U) = 6, 'string -> UnicodeString without loss');
  Check(string(U) = S, 'UnicodeString -> string without loss');

  Check(AnsiUpperCase(S) = 'ПРИВЕТ', 'AnsiUpperCase of Cyrillic');
  Check(AnsiLowerCase('ЁЖ') = 'ёж', 'AnsiLowerCase of Cyrillic');
  Check(Format('%s, %s!', [S, 'мир']) = 'привет, мир!', 'Format');

  Parts := TStringList.Create;
  for Ch in CodePoints('aё😀') do
    Parts.Add(Ch);
  Check((Parts.Count = 3) and (Parts[0] = 'a') and (Parts[1] = 'ё') and
    (Parts[2] = '😀'), 'for Ch in CodePoints: a, ё, 😀');
  Parts.Free;
  Check(CPLength(#$D0) = 1, 'a truncated character: no hang');

  Name := 'тест_файл_😀.txt';
  Assign(F, Name);
  Rewrite(F);
  WriteLn(F, 'строка');
  Close(F);
  Check(FileExists(Name), 'a file with a UTF-8 name is created');
  Reset(F);
  ReadLn(F, Line);
  Close(F);
  Check(Line = 'строка', 'UTF-8 text is read from the file');
  Check(DeleteFile(Name), 'the file with a UTF-8 name is deleted');

  WriteLn('Console output: ', S, ' 😀');
  if Failed > 0 then
  begin
    WriteLn('failed checks: ', Failed);
    Halt(1);
  end;
  WriteLn('all checks passed');
end.
