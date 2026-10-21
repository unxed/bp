{ SPDX-License-Identifier: MIT }
{ Benchmark (report only, no thresholds): the cost of TArenaRef<T>.Get against a plain arena reference
  (safe/SPEC.md, register H3, step 8 of #56). Built by tests/bench/run.sh with -O2; the CI job portable prints
  the table. Three loops over the same object: a plain reference, TArenaRef with debug checks off (release),
  TArenaRef taken with debug checks on (SAFE_DEBUG: a generation comparison on every Get). }
program bench_arena;

{$mode objfpc}{$H+}

uses
  SysUtils, Safe;

type
  TNode = class
  public
    Value: Int64;
  end;

  TNodeRef = specialize TArenaRef<TNode>;

const
  N = 200000000;

var
  Ar: TArena;
  Plain: TNode; // borrow: Ar
  Rel, Dbg: TNodeRef;
  Sum: Int64;

function Elapsed(Start: QWord): QWord;
begin
  Result := GetTickCount64 - Start;
  if Result = 0 then
    Result := 1;
end;

procedure Report(const Name: string; Ms: QWord; Base: QWord);
begin
  WriteLn(Format('%-34s %6d ms  %6.2f ns/op  x%.2f', [Name, Ms, Ms * 1e6 / N, Ms / Base]));
end;

procedure Run;
var
  I: Integer;
  T0, TPlain, TRel, TDbg: QWord;
begin
  Ar := TArena.Create;
  Rel := TNodeRef.Adopt(TNode.Create, Ar);
  SafeDebugChecks := True;
  Dbg := TNodeRef.Adopt(TNode.Create, Ar);
  SafeDebugChecks := False;
  Plain := Rel.Get;
  Plain.Value := 1;
  Dbg.Get.Value := 1;

  Sum := 0;
  T0 := GetTickCount64;
  for I := 1 to N do
    Inc(Sum, Plain.Value);
  TPlain := Elapsed(T0);

  T0 := GetTickCount64;
  for I := 1 to N do
    Inc(Sum, Rel.Get.Value);
  TRel := Elapsed(T0);

  T0 := GetTickCount64;
  for I := 1 to N do
    Inc(Sum, Dbg.Get.Value);
  TDbg := Elapsed(T0);

  WriteLn('bench_arena: ', N, ' reads of one field per loop (checksum ', Sum, ')');
  Report('plain reference', TPlain, TPlain);
  Report('TArenaRef.Get, checks off', TRel, TPlain);
  Report('TArenaRef.Get, SAFE_DEBUG', TDbg, TPlain);
  Ar.FreeAll;
end;

begin
  Run;
end.
