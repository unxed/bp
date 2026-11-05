{ SPDX-License-Identifier: MIT }
{ repro.pas with 64-bit index variables (SizeInt) in the swap loop.
  Build: fpc -O3 -al repro_idx64.pas; run: ./repro_idx64 [rounds] }
program repro_idx64;

{$mode objfpc}

const
  N = 256;

type
  TArr = array[0..N - 1] of LongInt;  { 32-bit, as int32_t in repro.c }

function Run(Rounds: LongInt): LongInt;
var
  A: TArr;
  R, T: LongInt;
  I, J: SizeInt;  { repro.pas: LongInt }
begin
  for I := 0 to N - 1 do
    A[I] := I;
  Result := 0;
  for R := 1 to Rounds do
  begin
    I := 0;
    J := R and (N - 1);
    while I < J do
    begin
      T := A[I];
      A[I] := A[J];
      A[J] := T;
      Inc(I);
      Dec(J);
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
