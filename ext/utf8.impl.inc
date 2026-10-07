{ SPDX-License-Identifier: MIT }
{ Better Pascal, ext/utf8 (реализация). }

{ ---------- UTF-8 ---------- }

{ Длина символа по ведущему байту. Битый байт или "хвост" — отдельный символ:
  обход никогда не зацикливается и не теряет байты. }
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

