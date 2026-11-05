{ SPDX-License-Identifier: MIT }
{ Tests of BPVec (ext/bpvec.pas): every kernel against the plain loop (Dot and Sum against the order BPVec
  documents), on every length from 0 to 40 and on 1000 and 1001, so the part in vectors and the rest both count;
  lengths that differ raise ERangeError. Exit code = number of failures. }
program test_vec;

{$mode objfpc}{$H+}

uses
  SysUtils, BPVec, BP;

type
  TDoubles = array of Double;
  TSingles = array of Single;
  TInts = array of LongInt;
  TInt64s = array of Int64;

var
  Failed: Integer = 0;
  Seed: Cardinal = 12345;

procedure Check(const Cond: Boolean; const What: string);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

function Next: LongInt;
begin
  Seed := Cardinal((QWord(Seed) * 1103515245 + 12345) and $FFFFFFFF);
  Result := LongInt(Seed shr 8) - (1 shl 23);
end;

function Doubles(const N: Integer): TDoubles;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := Next / 7.3;
end;

function Singles(const N: Integer): TSingles;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := Next / 7.3;
end;

function Ints(const N: Integer): TInts;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := Next * 255;   // up to 2^31 in size, of both signs
end;

function Int64s(const N: Integer): TInt64s;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := Int64(Next) * 1000003;
end;

{ the order of Dot of BPVec: W sums of I mod W (8 for Double), folded in halves, then the rest }
function DotD(const X, Y: TDoubles): Double;
var
  S: array[0..7] of Double;
  I, J, H, N: Integer;
begin
  N := Length(X);
  for J := 0 to 7 do
    S[J] := 0;
  I := 0;
  while I + 8 <= N do
  begin
    for J := 0 to 7 do
      S[J] := S[J] + X[I + J] * Y[I + J];
    Inc(I, 8);
  end;
  H := 4;
  while H >= 1 do
  begin
    for J := 0 to H - 1 do
      S[J] := S[J] + S[J + H];
    H := H div 2;
  end;
  Result := S[0];
  while I < N do
  begin
    Result := Result + X[I] * Y[I];
    Inc(I);
  end;
end;

{ Single: 16 sums }
function DotS(const X, Y: TSingles): Single;
var
  S: array[0..15] of Single;
  I, J, H, N: Integer;
begin
  N := Length(X);
  for J := 0 to 15 do
    S[J] := 0;
  I := 0;
  while I + 16 <= N do
  begin
    for J := 0 to 15 do
      S[J] := S[J] + X[I + J] * Y[I + J];
    Inc(I, 16);
  end;
  H := 8;
  while H >= 1 do
  begin
    for J := 0 to H - 1 do
      S[J] := S[J] + S[J + H];
    H := H div 2;
  end;
  Result := S[0];
  while I < N do
  begin
    Result := Result + X[I] * Y[I];
    Inc(I);
  end;
end;

function Ones(const N: Integer): TDoubles;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := 1;
end;

function OnesS(const N: Integer): TSingles;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := 1;
end;

function Same(const A, B: TDoubles): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(A) do
    if A[I] <> B[I] then
      Exit(False);
  Result := True;
end;

function SameS(const A, B: TSingles): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(A) do
    if A[I] <> B[I] then
      Exit(False);
  Result := True;
end;

procedure Floats;
var
  N, I: Integer;
  X, Y, R, E: TDoubles;
  XS, YS, RS, ES: TSingles;
  OkAxpy, OkScale, OkAdd, OkMul, OkDot, OkSum: Boolean;
  OkAxpyS, OkScaleS, OkAddS, OkMulS, OkDotS, OkSumS: Boolean;
  A: Double;
  AS1: Single;
begin
  OkAxpy := True; OkScale := True; OkAdd := True; OkMul := True; OkDot := True; OkSum := True;
  OkAxpyS := True; OkScaleS := True; OkAddS := True; OkMulS := True; OkDotS := True; OkSumS := True;
  for N := 0 to 1001 do
  begin
    if (N > 40) and (N < 1000) then
      Continue;
    A := Next / 3.1;
    X := Doubles(N);
    Y := Doubles(N);
    // the expected values are stored as the plain loop stores them (on x87 an expression keeps more bits)
    R := Copy(Y);
    E := Copy(Y);
    Axpy(R, X, A);
    for I := 0 to N - 1 do
      E[I] := E[I] + A * X[I];
    OkAxpy := OkAxpy and Same(R, E);
    R := Copy(Y);
    E := Copy(Y);
    Scale(R, A);
    for I := 0 to N - 1 do
      E[I] := E[I] * A;
    OkScale := OkScale and Same(R, E);
    R := Copy(Y);
    E := Copy(Y);
    BPVec.Add(R, X);
    for I := 0 to N - 1 do
      E[I] := E[I] + X[I];
    OkAdd := OkAdd and Same(R, E);
    R := Copy(Y);
    E := Copy(Y);
    Mul(R, X);
    for I := 0 to N - 1 do
      E[I] := E[I] * X[I];
    OkMul := OkMul and Same(R, E);
    OkDot := OkDot and (Dot(X, Y) = DotD(X, Y));
    OkSum := OkSum and (Sum(X) = DotD(X, Ones(N)));

    AS1 := Next / 3.1;
    XS := Singles(N);
    YS := Singles(N);
    RS := Copy(YS);
    ES := Copy(YS);
    Axpy(RS, XS, AS1);
    for I := 0 to N - 1 do
      ES[I] := ES[I] + AS1 * XS[I];
    OkAxpyS := OkAxpyS and SameS(RS, ES);
    RS := Copy(YS);
    ES := Copy(YS);
    Scale(RS, AS1);
    for I := 0 to N - 1 do
      ES[I] := ES[I] * AS1;
    OkScaleS := OkScaleS and SameS(RS, ES);
    RS := Copy(YS);
    ES := Copy(YS);
    BPVec.Add(RS, XS);
    for I := 0 to N - 1 do
      ES[I] := ES[I] + XS[I];
    OkAddS := OkAddS and SameS(RS, ES);
    RS := Copy(YS);
    ES := Copy(YS);
    Mul(RS, XS);
    for I := 0 to N - 1 do
      ES[I] := ES[I] * XS[I];
    OkMulS := OkMulS and SameS(RS, ES);
    OkDotS := OkDotS and (Dot(XS, YS) = DotS(XS, YS));
    OkSumS := OkSumS and (Sum(XS) = DotS(XS, OnesS(N)));
  end;
  Check(OkAxpy, 'Axpy of Double: the bits of the plain loop');
  Check(OkScale, 'Scale of Double: the bits of the plain loop');
  Check(OkAdd, 'Add of Double: the bits of the plain loop');
  Check(OkMul, 'Mul of Double: the bits of the plain loop');
  Check(OkDot, 'Dot of Double: the documented order');
  Check(OkSum, 'Sum of Double: the documented order');
  Check(OkAxpyS, 'Axpy of Single: the bits of the plain loop');
  Check(OkScaleS, 'Scale of Single: the bits of the plain loop');
  Check(OkAddS, 'Add of Single: the bits of the plain loop');
  Check(OkMulS, 'Mul of Single: the bits of the plain loop');
  Check(OkDotS, 'Dot of Single: the documented order');
  Check(OkSumS, 'Sum of Single: the documented order');
end;

{$push}{$Q-} // the reference wraps as the kernels do
procedure Integers;
var
  N, I: Integer;
  X, Y, R: TInts;
  X6, Y6, R6: TInt64s;
  S: Int64;
  OkAdd, OkSum, OkAdd6, OkSum6: Boolean;
begin
  OkAdd := True; OkSum := True; OkAdd6 := True; OkSum6 := True;
  for N := 0 to 1001 do
  begin
    if (N > 40) and (N < 1000) then
      Continue;
    X := Ints(N);
    Y := Ints(N);
    R := Copy(Y);
    BPVec.Add(R, X);
    S := 0;
    for I := 0 to N - 1 do
    begin
      OkAdd := OkAdd and (R[I] = LongInt(Y[I] + X[I]));
      S := S + X[I];
    end;
    OkSum := OkSum and (Sum(X) = S);
    X6 := Int64s(N);
    Y6 := Int64s(N);
    R6 := Copy(Y6);
    BPVec.Add(R6, X6);
    S := 0;
    for I := 0 to N - 1 do
    begin
      OkAdd6 := OkAdd6 and (R6[I] = Y6[I] + X6[I]);
      S := S + X6[I];
    end;
    OkSum6 := OkSum6 and (Sum(X6) = S);
  end;
  X := nil;
  SetLength(X, 9);
  for I := 0 to 8 do
    X[I] := High(LongInt);
  OkSum := OkSum and (Sum(X) = 9 * Int64(High(LongInt)));
  for I := 0 to 8 do
    X[I] := Low(LongInt);
  OkSum := OkSum and (Sum(X) = 9 * Int64(Low(LongInt)));
  Check(OkAdd, 'Add of LongInt: the plain loop, wrapping');
  Check(OkSum, 'Sum of LongInt: an Int64, with the sign of each element');
  Check(OkAdd6, 'Add of Int64: the plain loop, wrapping');
  Check(OkSum6, 'Sum of Int64: the plain loop, wrapping');
end;
{$pop}

procedure Lengths;
var
  X, Y: TDoubles;
  Raised: Boolean;
begin
  X := Doubles(5);
  Y := Doubles(4);
  Raised := False;
  try
    Axpy(Y, X, 2.0);
  except
    on ERangeError do
      Raised := True;
  end;
  Check(Raised, 'Axpy of arrays of different lengths raises ERangeError');
  Raised := False;
  try
    Dot(X, Y);
  except
    on ERangeError do
      Raised := True;
  end;
  Check(Raised, 'Dot of arrays of different lengths raises ERangeError');
end;

begin
  WriteLn('-- Vec');
  Floats;
  Integers;
  Lengths;
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
