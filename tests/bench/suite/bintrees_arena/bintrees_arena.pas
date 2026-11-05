{ SPDX-License-Identifier: MIT }
{ Benchmark suite (tests/bench/compare.sh): binary trees, the arena tier, the Bp version. The nodes of a tree are the
  elements of one growing dynamic array with 4-byte index links, the layout of bintrees_arena.c, .rs, .go and .goose;
  dropping a tree is setting the length to zero, and a loop of trees keeps the array. The nodes as objects of a region
  are the tier bintrees_region.
  Output: one line, the number of nodes counted. }
program bintrees_arena;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

const
  MaxDepth = 16;
  MinDepth = 4;
  None = High(Cardinal);

type
  TNode = record
    Left, Right: Cardinal;
  end;

  TPool = record
    Items: array of TNode;
    Len: Cardinal;
  end;

function Push(var A: TPool): Cardinal;
begin
  if A.Len = Cardinal(Length(A.Items)) then
    if A.Len = 0 then
      SetLength(A.Items, 16)
    else
      SetLength(A.Items, 2 * A.Len);
  A.Items[A.Len].Left := None;
  A.Items[A.Len].Right := None;
  Result := A.Len;
  Inc(A.Len);
end;

function Make(var A: TPool; const Depth: Integer): Cardinal;
var
  L, R: Cardinal;
begin
  Result := Push(A);
  if Depth > 0 then
  begin
    L := Make(A, Depth - 1);
    A.Items[Result].Left := L;
    R := Make(A, Depth - 1);
    A.Items[Result].Right := R;
  end;
end;

function Check(const A: TPool; const T: Cardinal): Int64;
begin
  Result := 1;
  if A.Items[T].Left <> None then
    Result := Result + Check(A, A.Items[T].Left) + Check(A, A.Items[T].Right);
end;

function Once(const Depth: Integer): Int64;
var
  A: TPool;
begin
  A.Len := 0;
  Result := Check(A, Make(A, Depth));
end;

function Many(const Depth: Integer; const Iterations: Int64): Int64;
var
  A: TPool;
  I: Int64;
begin
  A.Len := 0;
  Result := 0;
  for I := 1 to Iterations do
  begin
    Result := Result + Check(A, Make(A, Depth));
    A.Len := 0;
  end;
end;

var
  Long: TPool;
  Root: Cardinal;
  Total: Int64;
  Depth: Integer;
begin
  Total := Once(MaxDepth + 1);
  Long.Len := 0;
  Root := Make(Long, MaxDepth);
  Depth := MinDepth;
  while Depth <= MaxDepth do
  begin
    Total := Total + Many(Depth, Int64(1) shl (MaxDepth - Depth + MinDepth));
    Depth := Depth + 2;
  end;
  Total := Total + Check(Long, Root);
  WriteLn('bintrees ', Total);
end.
