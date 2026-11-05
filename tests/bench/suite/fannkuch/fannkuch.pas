{ SPDX-License-Identifier: MIT }
{ Benchmark suite (tests/bench/compare.sh): fannkuch, integers and arrays.
  For every permutation P of 0..N-1, in lexicographic order: copy it, then while the first element K is not 0, reverse
  the first K+1 elements and count one flip. The program prints the sum of the flip counts, added for the even
  permutations (the first is number 0) and subtracted for the odd ones, and the largest count.
  The elements and the counts are 32-bit, the indices 64-bit (SizeInt), as in the other languages.
  The other languages: fannkuch.c, fannkuch.rs, fannkuch.go (the same loops). }
program fannkuch;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

const
  N = 10;

type
  TPerm = array[0..N - 1] of Integer;

{ the number of flips of the permutation P }
function Flips(const P: TPerm): Integer;
var
  Q: TPerm;
  K, T: Integer;
  I, J: SizeInt;
begin
  Q := P;
  Result := 0;
  K := Q[0];
  while K <> 0 do
  begin
    I := 0;
    J := K;
    while I < J do
    begin
      T := Q[I];
      Q[I] := Q[J];
      Q[J] := T;
      Inc(I);
      Dec(J);
    end;
    Inc(Result);
    K := Q[0];
  end;
end;

{ the next permutation in lexicographic order; False after the last one }
function Next(var P: TPerm): Boolean;
var
  I, J: SizeInt;
  T: Integer;
begin
  I := N - 2;
  while (I >= 0) and (P[I] > P[I + 1]) do
    Dec(I);
  if I < 0 then
    Exit(False);
  J := N - 1;
  while P[J] < P[I] do
    Dec(J);
  T := P[I];
  P[I] := P[J];
  P[J] := T;
  I := I + 1;
  J := N - 1;
  while I < J do
  begin
    T := P[I];
    P[I] := P[J];
    P[J] := T;
    Inc(I);
    Dec(J);
  end;
  Result := True;
end;

var
  P: TPerm;
  I, F, MaxFlips: Integer;
  Index, Checksum: Int64;

begin
  for I := 0 to N - 1 do
    P[I] := I;
  Index := 0;
  Checksum := 0;
  MaxFlips := 0;
  repeat
    F := Flips(P);
    if F > MaxFlips then
      MaxFlips := F;
    if Index mod 2 = 0 then
      Checksum := Checksum + F
    else
      Checksum := Checksum - F;
    Inc(Index);
  until not Next(P);
  WriteLn('fannkuch ', Checksum, ' ', MaxFlips);
end.
