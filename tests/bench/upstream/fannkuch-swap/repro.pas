{ SPDX-License-Identifier: MIT }
{ The swap loop of fannkuch: reverse the first K+1 elements of a small array in place, many times.
  Build: fpc -O3 -al repro.pas; run: ./repro [rounds] }
program repro;

{$mode objfpc}

type
  TArr = array[0..15] of LongInt;  { 32-bit, as int32_t in repro.c }

function Run(Rounds: LongInt): LongInt;
var
  A: TArr;
  R, I, J, T: LongInt;
begin
  for I := 0 to 15 do
    A[I] := I;
  Result := 0;
  for R := 1 to Rounds do
  begin
    I := 0;
    J := R and 15;
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
  Rounds := 200000000;
  if ParamCount > 0 then
    Val(ParamStr(1), Rounds);
  WriteLn(Run(Rounds));
end.
