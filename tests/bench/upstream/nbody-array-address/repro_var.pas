{ SPDX-License-Identifier: MIT }
program repro_var;
{$mode objfpc}
const
  Dt = Double(0.001);
type
  TBody = record
    X, Y, Z, VX, VY, VZ, M: Double;
  end;
var
  B: array[0..4] of TBody;

procedure Pull(var P, Q: TBody);
var
  DX, DY, DZ, D2, Mag: Double;
begin
  DX := P.X - Q.X;
  DY := P.Y - Q.Y;
  DZ := P.Z - Q.Z;
  D2 := DX * DX + DY * DY + DZ * DZ;
  Mag := Dt / (D2 * Sqrt(D2));
  P.VX := P.VX - DX * Q.M * Mag;
  P.VY := P.VY - DY * Q.M * Mag;
  P.VZ := P.VZ - DZ * Q.M * Mag;
  Q.VX := Q.VX + DX * P.M * Mag;
  Q.VY := Q.VY + DY * P.M * Mag;
  Q.VZ := Q.VZ + DZ * P.M * Mag;
end;

procedure Run;
var
  I, J, S: Integer;
begin
  for S := 1 to 4000000 do
    for I := 0 to 3 do
      for J := I + 1 to 4 do
        Pull(B[I], B[J]);
end;

var
  K: Integer;
begin
  for K := 0 to 4 do
  begin
    B[K].X := K; B[K].Y := 2 * K; B[K].Z := 0.5 * K + 1;
    B[K].VX := 0; B[K].VY := 0; B[K].VZ := 0; B[K].M := K + 1;
  end;
  Run;
  WriteLn(B[0].VX:0:6, ' ', B[4].VZ:0:6);
end.
