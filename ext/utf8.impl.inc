{ SPDX-License-Identifier: MIT }
{ Better Pascal, ext/utf8 (implementation). }

{ ---------- UTF-8 ---------- }

{ The length of a character from its lead byte. A broken byte or a lone continuation byte is a character of its own:
  the walk never loops and never loses bytes. }
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

