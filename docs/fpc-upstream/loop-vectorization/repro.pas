{ SPDX-License-Identifier: MIT }
{ A loop over arrays of Double that gcc -O3 vectorizes (two doubles per SSE2 instruction); FPC emits one double per
  instruction. Build: fpc -O3 -al repro.pas; run: ./repro [rounds] }
program repro;

{$mode objfpc}

const
  N = 1024;

type
  TVec = array[0..N - 1] of Double;

procedure Axpy(var Y: TVec; const X: TVec; const A: Double);
var
  I: SizeInt;
begin
  for I := 0 to N - 1 do
    Y[I] := Y[I] + A * X[I];
end;

var
  X, Y: TVec;
  I: SizeInt;
  Rounds, R: LongInt;
  S: Double;
begin
  Rounds := 2000000;
  if ParamCount > 0 then
    Val(ParamStr(1), Rounds);
  for I := 0 to N - 1 do
  begin
    X[I] := I * 0.5;
    Y[I] := 0;
  end;
  for R := 1 to Rounds do
    Axpy(Y, X, 1.0e-9);
  S := 0;
  for I := 0 to N - 1 do
    S := S + Y[I];
  WriteLn(S:0:6);
end.
