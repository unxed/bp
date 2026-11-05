{ SPDX-License-Identifier: MIT }
{ Benchmark suite (tests/bench/compare.sh): binary trees, an allocation-heavy tree.
  The program makes complete binary trees of growing depth and counts their nodes; every tree is built, walked once and
  dropped. The trees of the loop live in one region that is reset after each walk (SPEC §20: "a loop uses Reset"); the
  long-lived tree has a region of its own (TRegion and TRegionObject of unit BP). The other languages: bintrees.c
  (malloc and free), bintrees.rs (Box), bintrees.go (the collector).
  Output: one line, the number of nodes counted. }
program bintrees;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

type
  TNode = class(TRegionObject)
    Left, Right: TNode;
  end;

const
  MaxDepth = 16;
  MinDepth = 4;

function Make(const Depth: Integer): TNode;
begin
  Result := TNode.Create;
  if Depth > 0 then
  begin
    Result.Left := Make(Depth - 1);
    Result.Right := Make(Depth - 1);
  end;
end;

function Check(T: TNode): Int64;
begin
  Result := 1;
  if T.Left <> nil then
    Result := Result + Check(T.Left) + Check(T.Right);
end;

{ the nodes of one tree of the given depth, in a region of its own }
function Stretch(const Depth: Integer): Int64;
var
  R: TRegion;
begin
  R := TRegion.Create;
  Result := Check(Make(Depth));
end;

{ Iterations trees of the given depth, one region reset after each }
function Many(const Depth: Integer; const Iterations: Int64): Int64;
var
  R: TRegion;
  I: Int64;
begin
  Result := 0;
  R := TRegion.Create;
  for I := 1 to Iterations do
  begin
    Result := Result + Check(Make(Depth));
    R.Reset;
  end;
end;

function Run: Int64;
var
  R: TRegion;
  Long: TNode;
  Depth: Integer;
begin
  Result := Stretch(MaxDepth + 1);
  R := TRegion.Create;
  Long := Make(MaxDepth);
  Depth := MinDepth;
  while Depth <= MaxDepth do
  begin
    Result := Result + Many(Depth, Int64(1) shl (MaxDepth - Depth + MinDepth));
    Depth := Depth + 2;
  end;
  Result := Result + Check(Long);
end;

begin
  WriteLn('bintrees ', Run);
end.
