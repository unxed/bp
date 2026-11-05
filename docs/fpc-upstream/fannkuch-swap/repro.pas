{ SPDX-License-Identifier: MIT }
{ The swap loop of fannkuch: reverse the first K+1 elements of an array in place, many times.
  Build: fpc -O3 -al repro.pas; run: ./repro [rounds] }
program repro;

{$mode objfpc}

const
  N = 256;

type
  TArr = array[0..N - 1] of LongInt;  { 32-bit, as int32_t in repro.c }

function Run(Rounds: LongInt): LongInt;
var
  A: TArr;
  R, I, J, T: LongInt;  { repro_idx64.pas: I, J: SizeInt }
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
