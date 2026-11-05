{ SPDX-License-Identifier: MIT }
{ Benchmark suite (tests/bench/compare.sh): binary trees, the tier with one heap block per node.
  The program makes complete binary trees of growing depth and counts their nodes; every tree is built, walked once and
  dropped node by node. A node is a plain class object on the heap; Drop frees each one (the destructor call is marked
  UNSAFE: the dialect closes .Free). The other languages: bintrees.c (malloc and free), bintrees.rs (Box), bintrees.go
  (the collector); Goose has no heap of single blocks. The tier with one arena per tree is bintrees_arena.
  Output: one line, the number of nodes counted. }
program bintrees;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

type
  TNode = class
    // borrow: Drop frees every node of a tree
    Left, Right: TNode;
  end;

const
  MaxDepth = 16;
  MinDepth = 4;

function Make(const Depth: Integer): TNode;
begin
  // UNSAFE: the benchmark owns each node by hand; Drop frees it
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

{ frees every node of the tree, children first }
procedure Drop(T: TNode);
begin
  if T.Left <> nil then
  begin
    Drop(T.Left);
    Drop(T.Right);
  end;
  // UNSAFE: the benchmark frees each node by hand, as the C version calls free
  T.Destroy;
end;

function Once(const Depth: Integer): Int64;
var
  T: TNode;
begin
  T := Make(Depth);
  Result := Check(T);
  Drop(T);
end;

function Many(const Depth: Integer; const Iterations: Int64): Int64;
var
  I: Int64;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + Once(Depth);
end;

function Run: Int64;
var
  Long: TNode;
  Depth: Integer;
begin
  Result := Once(MaxDepth + 1);
  Long := Make(MaxDepth);
  Depth := MinDepth;
  while Depth <= MaxDepth do
  begin
    Result := Result + Many(Depth, Int64(1) shl (MaxDepth - Depth + MinDepth));
    Depth := Depth + 2;
  end;
  Result := Result + Check(Long);
  Drop(Long);
end;

begin
  WriteLn('bintrees ', Run);
end.
