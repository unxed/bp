{ Тест UTF8Everywhere. Обратите внимание: в uses модуля нет,
  его подставляет -FaUTF8Everywhere из utf8.cfg. Код возврата 0 = всё прошло. }
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
  Check(StringCodePage(S + IntToStr(1)) = CP_UTF8, 'строка из выражения в UTF-8');
  Check(Length(S) = 12, 'Length в байтах: 12');
  Check(CPLength(S) = 6, 'CPLength в символах: 6');
  Check(Pos('ве', S) = 7, 'Pos по байтам: 7');
  Check(Copy(S, Pos('ве', S), MaxInt) = 'вет', 'Copy с позиции Pos');

  U := S;
  Check(Length(U) = 6, 'string -> UnicodeString без потерь');
  Check(string(U) = S, 'UnicodeString -> string без потерь');

  Check(AnsiUpperCase(S) = 'ПРИВЕТ', 'AnsiUpperCase кириллицы');
  Check(AnsiLowerCase('ЁЖ') = 'ёж', 'AnsiLowerCase кириллицы');
  Check(Format('%s, %s!', [S, 'мир']) = 'привет, мир!', 'Format');

  Parts := TStringList.Create;
  for Ch in CodePoints('aё😀') do
    Parts.Add(Ch);
  Check((Parts.Count = 3) and (Parts[0] = 'a') and (Parts[1] = 'ё') and
    (Parts[2] = '😀'), 'for Ch in CodePoints: a, ё, 😀');
  Parts.Free;
  Check(CPLength(#$D0) = 1, 'обрезанный символ: не зависаем');

  Name := 'тест_файл_😀.txt';
  Assign(F, Name);
  Rewrite(F);
  WriteLn(F, 'строка');
  Close(F);
  Check(FileExists(Name), 'файл с UTF-8 именем создан');
  Reset(F);
  ReadLn(F, Line);
  Close(F);
  Check(Line = 'строка', 'чтение UTF-8 текста из файла');
  Check(DeleteFile(Name), 'удаление файла с UTF-8 именем');

  WriteLn('Вывод в консоль: ', S, ' 😀');
  if Failed > 0 then
  begin
    WriteLn('провалено проверок: ', Failed);
    Halt(1);
  end;
  WriteLn('все проверки прошли');
end.
