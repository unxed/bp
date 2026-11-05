{ SPDX-License-Identifier: MIT }
{ Benchmark suite (tests/bench/compare.sh): axpy, a loop over arrays of floating point. Y[I] := Y[I] + A * X[I] over
  two arrays of 1024 doubles, 2,000,000 rounds. FPC does not vectorize a loop, so the Bp version calls the kernel of
  unit BPVec (SSE2 on x86_64), which gives the bits of the plain loop; the other languages write the loop (gcc -O2
  vectorizes it). The sum at the end is a plain loop in every language, so all print the same line: the sum of Y in
  millionths, rounded down after adding one half.
  The other languages: axpy.c, axpy.rs, axpy.go, axpy.goose. }
program axpy;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, BPVec, BP;

const
  N = 1024;
  Rounds = 2000000;

var
  X, Y: array of Double;
  I, R: SizeInt;
  S: Double;
begin
  SetLength(X, N);
  SetLength(Y, N);
  for I := 0 to N - 1 do
  begin
    X[I] := I * 0.5;
    Y[I] := 0;
  end;
  for R := 1 to Rounds do
    BPVec.Axpy(Y, X, 1.0e-9);   // the name of the program is axpy too
  S := 0;
  for I := 0 to N - 1 do
    S := S + Y[I];
  WriteLn('axpy ', Floor64(S * 1e6 + 0.5));
end.
