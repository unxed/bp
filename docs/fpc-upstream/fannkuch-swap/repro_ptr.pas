{ SPDX-License-Identifier: MIT }
{ repro.pas with pointers instead of indexes in the swap loop.
  Build: fpc -O3 -al repro_ptr.pas; run: ./repro_ptr [rounds] }
program repro_ptr;

{$mode objfpc}

const
  N = 256;

type
  TArr = array[0..N - 1] of LongInt;

function Run(Rounds: LongInt): LongInt;
var
  A: TArr;
  R, T: LongInt;
  P, Q: PLongInt;
begin
  for R := 0 to N - 1 do
    A[R] := R;
  Result := 0;
  for R := 1 to Rounds do
  begin
    P := @A[0];
    Q := @A[R and (N - 1)];
    while P < Q do
    begin
      T := P^;
      P^ := Q^;
      Q^ := T;
      Inc(P);
      Dec(Q);
    end;
    Result := Result + A[0];
  end;
end;

var
  Rounds: LongInt;
begin
  Rounds := 10000000;
  if ParamCount > 0 then
    Val(ParamStr(1), Rounds);
  WriteLn(Run(Rounds));
end.
