{ UTF8Everywhere: string = UTF-8, без оговорок.

  Подключать руками не нужно: utf8.cfg содержит -FaUTF8Everywhere,
  и компилятор сам вставляет этот модуль первым в uses каждой программы.

  Что делает:
  - прячет "менеджер строк" (cwstring на Unix) внутрь себя;
  - объявляет UTF-8 кодировкой по умолчанию для строк, имён файлов и консоли;
  - даёт обход строки по символам: for Ch in CodePoints(S), где Ch тоже string.

  Length(S) и S[i] остаются в байтах. Это не баг, а принцип UTF-8 Everywhere:
  индексы в байтах дешёвые и однозначные, Pos/Copy/Delete на них корректны,
  потому что UTF-8 самосинхронизируется. Символы нужны редко, для них CodePoints. }
unit UTF8Everywhere;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  {$ifdef unix}cwstring,{$endif} // UTF-8 <-> UTF-16 и регистр букв через libc
  {$ifdef windows}Windows,{$endif}
  SysUtils;

type
  { Перечислитель символов (code points). Current: один символ как string. }
  TCodePointEnumerator = record
  private
    FS: RawByteString;
    FPos, FLen: SizeInt;
    function GetCurrent: string;
  public
    function GetEnumerator: TCodePointEnumerator;
    function MoveNext: Boolean;
    property Current: string read GetCurrent;
  end;

{ for Ch in CodePoints('aё😀') do ...  // 'a', 'ё', '😀' }
function CodePoints(const S: string): TCodePointEnumerator;
{ Длина в символах (code points), а не в байтах. }
function CPLength(const S: string): SizeInt;

implementation

{ Длина символа по ведущему байту. Битый байт или "хвост" считаем
  отдельным символом: обход никогда не зацикливается и не теряет байты. }
function CPByteLen(B: Byte): SizeInt; inline;
begin
  case B of
    $C0..$DF: Result := 2;
    $E0..$EF: Result := 3;
    $F0..$F7: Result := 4;
  else
    Result := 1;
  end;
end;

function TCodePointEnumerator.GetCurrent: string;
begin
  Result := Copy(FS, FPos, FLen);
end;

function TCodePointEnumerator.GetEnumerator: TCodePointEnumerator;
begin
  Result := Self;
end;

function TCodePointEnumerator.MoveNext: Boolean;
begin
  Inc(FPos, FLen);
  Result := FPos <= Length(FS);
  if Result then
  begin
    FLen := CPByteLen(Byte(FS[FPos]));
    if FLen > Length(FS) - FPos + 1 then // обрезанный символ в конце строки
      FLen := Length(FS) - FPos + 1;
  end;
end;

function CodePoints(const S: string): TCodePointEnumerator;
begin
  Result.FS := S;
  Result.FPos := 1;
  Result.FLen := 0;
end;

function CPLength(const S: string): SizeInt;
var
  Ch: string;
begin
  Result := 0;
  for Ch in CodePoints(S) do
    Inc(Result);
end;

initialization
  // Кодировка string по умолчанию (а с ней и всех неявных конверсий).
  DefaultSystemCodePage := CP_UTF8;
  // Имена файлов: на входе в RTL и на выходе (FindFirst, GetCurrentDir...).
  DefaultFileSystemCodePage := CP_UTF8;
  DefaultRTLFileSystemCodePage := CP_UTF8;
  // Консоль и стандартные потоки.
  SetTextCodePage(Input, CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(ErrOutput, CP_UTF8);
  SetTextCodePage(StdOut, CP_UTF8);
  SetTextCodePage(StdErr, CP_UTF8);
  {$ifdef windows}
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  {$endif}
end.
