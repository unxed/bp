{ SPDX-License-Identifier: MIT }
{ Benchmark suite (tests/bench/compare.sh): n-body, floating point.
  A heavy body and four light ones move under their mutual gravitation (G = 1). One step: the velocities change by the
  pull of every pair (time step Dt), then the positions change by the new velocities. The program prints the energy
  of the system before and after Steps steps, in millionths, rounded down after adding one half, so that all languages print the same line.
  The other languages: nbody.c, nbody.rs, nbody.go, nbody.goose (the same bodies and the same order of operations). }
program nbody;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, BP;

const
  Steps = 5000000;
  Dt = Double(0.001);
  Count = 5;

type
  TBody = record
    X, Y, Z, VX, VY, VZ, M: Double;
  end;

var
  Bodies: array[0..Count - 1] of TBody;

procedure Init;
begin
  Bodies[0].X := 0;       Bodies[0].Y := 0;     Bodies[0].Z := 0;
  Bodies[0].VX := 0;      Bodies[0].VY := 0;    Bodies[0].VZ := 0;
  Bodies[0].M := 1000;

  Bodies[1].X := 4;       Bodies[1].Y := 0;     Bodies[1].Z := 0.5;
  Bodies[1].VX := 0;      Bodies[1].VY := 15.8113883;  Bodies[1].VZ := 0.1;
  Bodies[1].M := 1;

  Bodies[2].X := 0;       Bodies[2].Y := 8;     Bodies[2].Z := -0.3;
  Bodies[2].VX := -11.1803399;  Bodies[2].VY := 0;  Bodies[2].VZ := 0.05;
  Bodies[2].M := 2;

  Bodies[3].X := -12;     Bodies[3].Y := 0;     Bodies[3].Z := 0.8;
  Bodies[3].VX := 0;      Bodies[3].VY := -9.12870929; Bodies[3].VZ := -0.07;
  Bodies[3].M := 3;

  Bodies[4].X := 0;       Bodies[4].Y := -16;   Bodies[4].Z := -1;
  Bodies[4].VX := 7.90569415;  Bodies[4].VY := 0;  Bodies[4].VZ := 0.04;
  Bodies[4].M := 0.5;
end;

{ The pull between two bodies. A and B are var parameters, so the address of each body is taken once per pair: FPC
  computes the address of Bodies[I] again after every store into the array (SPEC §25.2, n-body). }
procedure Pull(var A, B: TBody);
var
  DX, DY, DZ, D2, Mag: Double;
begin
  DX := A.X - B.X;
  DY := A.Y - B.Y;
  DZ := A.Z - B.Z;
  D2 := DX * DX + DY * DY + DZ * DZ;
  Mag := Dt / (D2 * Sqrt(D2));
  A.VX := A.VX - DX * B.M * Mag;
  A.VY := A.VY - DY * B.M * Mag;
  A.VZ := A.VZ - DZ * B.M * Mag;
  B.VX := B.VX + DX * A.M * Mag;
  B.VY := B.VY + DY * A.M * Mag;
  B.VZ := B.VZ + DZ * A.M * Mag;
end;

procedure Drift(var A: TBody);
begin
  A.X := A.X + Dt * A.VX;
  A.Y := A.Y + Dt * A.VY;
  A.Z := A.Z + Dt * A.VZ;
end;

procedure Advance;
var
  I, J: SizeInt;
begin
  for I := 0 to Count - 2 do
    for J := I + 1 to Count - 1 do
      Pull(Bodies[I], Bodies[J]);
  for I := 0 to Count - 1 do
    Drift(Bodies[I]);
end;

function Energy: Double;
var
  I, J: SizeInt;
  DX, DY, DZ: Double;
begin
  Result := 0;
  for I := 0 to Count - 1 do
  begin
    Result := Result + 0.5 * Bodies[I].M *
      (Bodies[I].VX * Bodies[I].VX + Bodies[I].VY * Bodies[I].VY + Bodies[I].VZ * Bodies[I].VZ);
    for J := I + 1 to Count - 1 do
    begin
      DX := Bodies[I].X - Bodies[J].X;
      DY := Bodies[I].Y - Bodies[J].Y;
      DZ := Bodies[I].Z - Bodies[J].Z;
      Result := Result - Bodies[I].M * Bodies[J].M / Sqrt(DX * DX + DY * DY + DZ * DZ);
    end;
  end;
end;

var
  Step: Integer;
  Before: Int64;

begin
  Init;
  Before := Floor64(Energy() * 1e6 + 0.5);
  for Step := 1 to Steps do
    Advance;
  WriteLn('nbody ', Before, ' ', Floor64(Energy() * 1e6 + 0.5));
end.
