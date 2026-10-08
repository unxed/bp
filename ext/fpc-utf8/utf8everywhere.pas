{ UTF8Everywhere: string = UTF-8, with no exceptions.

  No need to add it by hand: utf8.cfg holds -FaUTF8Everywhere,
  and the compiler inserts this unit first into the uses of every program.

  What it does:
  - hides the string manager (cwstring on Unix) inside itself;
  - makes UTF-8 the default encoding of strings, file names and the console;
  - walks a string by characters: for Ch in CodePoints(S), where Ch is a string too.

  Length(S) and S[i] stay in bytes. This is not a bug but the UTF-8 Everywhere principle:
  byte indexes are cheap and unambiguous, and Pos/Copy/Delete are correct on them
  because UTF-8 is self-synchronizing. Characters are rarely needed; CodePoints is there for them. }
unit UTF8Everywhere;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  {$ifdef unix}cwstring,{$endif} // UTF-8 <-> UTF-16 and letter case through libc
  {$ifdef windows}Windows,{$endif}
  SysUtils;

type
  { An enumerator of characters (code points). Current: one character as a string. }
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
{ The length in characters (code points), not in bytes. }
function CPLength(const S: string): SizeInt;

implementation

{ The length of a character from its lead byte. A broken byte or a lone continuation byte counts
  as a character of its own: the walk never loops and never loses bytes. }
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
    if FLen > Length(FS) - FPos + 1 then // a truncated character at the end of the string
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
  // The default encoding of string (and with it of all implicit conversions).
  DefaultSystemCodePage := CP_UTF8;
  // File names: into the RTL and out of it (FindFirst, GetCurrentDir...).
  DefaultFileSystemCodePage := CP_UTF8;
  DefaultRTLFileSystemCodePage := CP_UTF8;
  // The console and the standard streams.
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
