{
    Free Pascal IDE on tv3: text of the editor as UTF-8.

    A line of the editor is a string of bytes. In UTF-8 mode (the default; not in a DOS build, where the text is one
    byte per character) one COLUMN of the editor is one character: a valid UTF-8 sequence, or a single byte that
    is not part of one (such a byte is kept as it is, and shown through the code page by tv3). Tabs are expanded
    to spaces before the columns are counted (the editor's "display text"), so a column is also one cell of the
    screen, except for wide characters (CJK), which take two cells when they are drawn.
    The functions take and give 0-based columns.
}
unit WUtf8;

{$mode objfpc}
{$H-}

interface

var
  { False: one byte is one column (DOS; or a file in a one-byte code page) }
  Utf8Text: boolean = {$ifdef go32v2}false{$else}true{$endif};

{ the number of bytes of the character that starts at byte Idx (1-based) of S: 1 for ASCII and for a stray byte }
function U8CharBytes(const S: string; Idx: integer): integer;
{ the number of columns of S }
function U8Len(const S: string): integer;
{ the byte index (1-based) where column Col starts; Length(S)+1 when Col is at or after the end }
function U8Idx(const S: string; Col: integer): integer;
{ the column (0-based) of the byte at index Idx; Idx may be Length(S)+1 }
function U8Col(const S: string; Idx: integer): integer;
{ Cnt columns from column Col }
function U8Copy(const S: string; Col, Cnt: integer): string;
{ the character at column Col as a string; '' beyond the end }
function U8Char(const S: string; Col: integer): string;
procedure U8Delete(var S: string; Col, Cnt: integer);
{ inserts Sub before column Col (at the end when Col is beyond it) }
procedure U8Insert(const Sub: string; var S: string; Col: integer);
{ the code point of the character at column Col; the byte itself for a stray byte; 0 beyond the end }
function U8CodePoint(const S: string; Col: integer): longword;
{ the UTF-8 of a code point }
function U8Encode(CP: longword): string;
{ the width in screen cells of the columns Col..Col+Cnt-1 (wide characters are 2 cells) }
function U8Cells(const S: string; Col, Cnt: integer): integer;
{ the byte index of the start of the character before the one at byte index Idx (1 when there is none) }
function U8PrevIdx(const S: string; Idx: integer): integer;
{ the first byte of the character at column Col (' ' beyond the end): for the tests of ASCII classes; a multi-byte character gives its lead byte (>= #$C2) }
function U8ColChar(const S: string; Col: integer): char;
{ S padded with blanks to Cols columns (S is not cut) }
function U8Pad(const S: string; Cols: integer): string;
{ does the string consist of single-byte columns only? }
function U8IsAscii(const S: string): boolean;
{ upper/lower case of the characters (the letters of Latin, Greek, Cyrillic, ...; the rest is left alone) }
function U8Upper(const S: string): string;
function U8Lower(const S: string): string;

implementation

uses
  SysUtils, TvUtf8;

function U8CharBytes(const S: string; Idx: integer): integer;
var
  CP: longword;
  Used: integer;
begin
  if (Idx < 1) or (Idx > Length(S)) then
    Exit(0);
  if (not Utf8Text) or (Byte(S[Idx]) < $80) then
    Exit(1);
  if Utf8Decode(@S[Idx], Length(S) - Idx + 1, CP, Used) and (Used > 1) then
    Result := Used
  else
    Result := 1;
end;

function U8PrevIdx(const S: string; Idx: integer): integer;
var
  I, N: integer;
begin
  Result := 1;
  I := 1;
  while I < Idx do
  begin
    Result := I;
    N := U8CharBytes(S, I);
    if N < 1 then N := 1;
    Inc(I, N);
  end;
end;

function U8ColChar(const S: string; Col: integer): char;
var
  I: integer;
begin
  I := U8Idx(S, Col);
  if I > Length(S) then Result := ' ' else Result := S[I];
end;

function U8Pad(const S: string; Cols: integer): string;
var
  N: integer;
begin
  N := U8Len(S);
  Result := S;
  if N < Cols then
    Result := Result + StringOfChar(' ', Cols - N);
end;

function U8IsAscii(const S: string): boolean;
var
  I: integer;
begin
  for I := 1 to Length(S) do
    if Byte(S[I]) >= $80 then
      Exit(false);
  Result := true;
end;

function U8Len(const S: string): integer;
var
  I: integer;
begin
  if (not Utf8Text) or U8IsAscii(S) then
    Exit(Length(S));
  Result := 0;
  I := 1;
  while I <= Length(S) do
  begin
    Inc(I, U8CharBytes(S, I));
    Inc(Result);
  end;
end;

function U8Idx(const S: string; Col: integer): integer;
var
  C: integer;
begin
  if Col <= 0 then
    Exit(1);
  if (not Utf8Text) then
    begin
      if Col >= Length(S) then Exit(Length(S) + 1);
      Exit(Col + 1);
    end;
  Result := 1;
  C := 0;
  while (Result <= Length(S)) and (C < Col) do
  begin
    Inc(Result, U8CharBytes(S, Result));
    Inc(C);
  end;
end;

function U8Col(const S: string; Idx: integer): integer;
var
  I: integer;
begin
  if not Utf8Text then
    Exit(Idx - 1);
  Result := 0;
  I := 1;
  while (I < Idx) and (I <= Length(S)) do
  begin
    Inc(I, U8CharBytes(S, I));
    Inc(Result);
  end;
  { Idx beyond the end: the columns past it are one byte each }
  if Idx > Length(S) + 1 then
    Inc(Result, Idx - Length(S) - 1);
end;

function U8Copy(const S: string; Col, Cnt: integer): string;
var
  A, B: integer;
begin
  if Cnt <= 0 then
    Exit('');
  if Col < 0 then
  begin
    Inc(Cnt, Col);
    Col := 0;
    if Cnt <= 0 then
      Exit('');
  end;
  A := U8Idx(S, Col);
  B := U8Idx(S, Col + Cnt);
  Result := Copy(S, A, B - A);
end;

function U8Char(const S: string; Col: integer): string;
begin
  Result := U8Copy(S, Col, 1);
end;

procedure U8Delete(var S: string; Col, Cnt: integer);
var
  A, B: integer;
begin
  if Cnt <= 0 then
    Exit;
  A := U8Idx(S, Col);
  B := U8Idx(S, Col + Cnt);
  Delete(S, A, B - A);
end;

procedure U8Insert(const Sub: string; var S: string; Col: integer);
begin
  Insert(Sub, S, U8Idx(S, Col));
end;

function U8CodePoint(const S: string; Col: integer): longword;
var
  I, Used: integer;
  CP: longword;
begin
  I := U8Idx(S, Col);
  if I > Length(S) then
    Exit(0);
  if Utf8Text and (Byte(S[I]) >= $80) and Utf8Decode(@S[I], Length(S) - I + 1, CP, Used) and (Used > 1) then
    Result := CP
  else
    Result := Byte(S[I]);
end;

function U8Encode(CP: longword): string;
var
  Buf: array[0..7] of byte;
  N: integer;
begin
  if (CP < $80) or (not Utf8Text) then
    Exit(Chr(Byte(CP)));
  N := Utf8Encode(CP, @Buf[0]);
  SetLength(Result, N);
  Move(Buf[0], Result[1], N);
end;

function U8Cells(const S: string; Col, Cnt: integer): integer;
var
  I, N, Used: integer;
  CP: longword;
begin
  Result := 0;
  if Cnt <= 0 then
    Exit;
  if (not Utf8Text) or U8IsAscii(S) then
    Exit(Cnt);
  I := U8Idx(S, Col);
  N := 0;
  while N < Cnt do
  begin
    if I > Length(S) then
    begin
      Inc(Result, Cnt - N);       { past the end: blanks }
      Break;
    end;
    if (Byte(S[I]) >= $80) and Utf8Decode(@S[I], Length(S) - I + 1, CP, Used) and (Used > 1) then
    begin
      Inc(Result, CharWidth(CP));
      Inc(I, Used);
    end
    else
    begin
      Inc(Result);
      Inc(I);
    end;
    Inc(N);
  end;
end;

{ the case of a code point: ASCII, Latin-1, Latin Extended-A, Greek, Cyrillic (no tables, no Unicode manager) }
function CPUpper(CP: longword): longword;
begin
  Result := CP;
  if (CP >= $61) and (CP <= $7A) then Result := CP - $20
  else if (CP >= $E0) and (CP <= $FE) and (CP <> $F7) then Result := CP - $20
  else if CP = $FF then Result := $178
  else if (CP >= $100) and (CP <= $17F) then
  begin
    if ((CP >= $139) and (CP <= $148)) or ((CP >= $179) and (CP <= $17E)) then
    begin
      if Odd(CP) = false then Result := CP - 1;
    end
    else if (CP <> $131) and (CP <> $138) and (CP <> $149) and (CP <> $17F) and Odd(CP) then
      Result := CP - 1;
  end
  else if (CP >= $3B1) and (CP <= $3C9) and (CP <> $3C2) then Result := CP - $20
  else if (CP >= $3AC) and (CP <= $3AF) then Result := CP - $26 + 0
  else if (CP >= $430) and (CP <= $44F) then Result := CP - $20
  else if (CP >= $450) and (CP <= $45F) then Result := CP - $50;
end;

function CPLower(CP: longword): longword;
begin
  Result := CP;
  if (CP >= $41) and (CP <= $5A) then Result := CP + $20
  else if (CP >= $C0) and (CP <= $DE) and (CP <> $D7) then Result := CP + $20
  else if CP = $178 then Result := $FF
  else if (CP >= $100) and (CP <= $17F) then
  begin
    if ((CP >= $139) and (CP <= $148)) or ((CP >= $179) and (CP <= $17E)) then
    begin
      if Odd(CP) then Result := CP + 1;
    end
    else if (CP <> $130) and (CP <> $138) and (CP <> $149) and (CP <> $17F) and (not Odd(CP)) then
      Result := CP + 1;
  end
  else if (CP >= $391) and (CP <= $3A9) then Result := CP + $20
  else if (CP >= $410) and (CP <= $42F) then Result := CP + $20
  else if (CP >= $400) and (CP <= $40F) then Result := CP + $50;
end;

function MapCase(const S: string; Up: boolean): string;
var
  Col: integer;
  CP, M: longword;
begin
  if U8IsAscii(S) or (not Utf8Text) then
  begin
    Result := S;
    for Col := 1 to Length(Result) do
      if Up then
        Result[Col] := UpCase(Result[Col])
      else if Result[Col] in ['A'..'Z'] then
        Result[Col] := Chr(Ord(Result[Col]) + 32);
    Exit;
  end;
  Result := '';
  for Col := 0 to U8Len(S) - 1 do
  begin
    CP := U8CodePoint(S, Col);
    if (CP < $80) and (U8CharBytes(S, U8Idx(S, Col)) = 1) and (Byte(S[U8Idx(S, Col)]) < $80) or (Length(U8Char(S, Col)) = 1) then
      Result := Result + U8Char(S, Col)      { ASCII or a stray byte: not touched (ASCII below) }
    else
    begin
      if Up then M := CPUpper(CP) else M := CPLower(CP);
      Result := Result + U8Encode(M);
    end;
    if (Length(U8Char(S, Col)) = 1) and (Byte(S[U8Idx(S, Col)]) < $80) then
    begin
      if Up then Result[Length(Result)] := UpCase(Result[Length(Result)])
      else if Result[Length(Result)] in ['A'..'Z'] then
        Result[Length(Result)] := Chr(Ord(Result[Length(Result)]) + 32);
    end;
  end;
end;


function U8Upper(const S: string): string;
begin
  Result := MapCase(S, true);
end;

function U8Lower(const S: string): string;
begin
  Result := MapCase(S, false);
end;

end.
