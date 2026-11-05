{ SPDX-License-Identifier: MIT }
{ A record parameter passed in two registers is stored to the stack and read back on every use.
  Build: fpc -O3 -al repro.pas; run: ./repro [rounds] }
program repro;

{$mode objfpc}

const
  None = High(Cardinal);
  Depth = 16;

type
  TNode = record
    Left, Right: Cardinal;
  end;
  TPool = record          { 16 bytes: passed in two registers by value }
    Items: array of TNode;
    Len: Cardinal;
  end;

function Make(var A: TPool; const D: Integer): Cardinal;
var
  L, R: Cardinal;
begin
  Result := A.Len;
  Inc(A.Len);
  A.Items[Result].Left := None;
  A.Items[Result].Right := None;
  if D > 0 then
  begin
    L := Make(A, D - 1);
    A.Items[Result].Left := L;
    R := Make(A, D - 1);
    A.Items[Result].Right := R;
  end;
end;

{ the same as repro.pas with constref A }
function Check(constref A: TPool; const T: Cardinal): Int64;
begin
  Result := 1;
  if A.Items[T].Left <> None then
    Result := Result + Check(A, A.Items[T].Left) + Check(A, A.Items[T].Right);
end;

var
  A: TPool;
  Root: Cardinal;
  Rounds, I: LongInt;
  Sum: Int64;
begin
  Rounds := 400;
  if ParamCount > 0 then
    Val(ParamStr(1), Rounds);
  SetLength(A.Items, 1 shl (Depth + 1));
  A.Len := 0;
  Root := Make(A, Depth);
  Sum := 0;
  for I := 1 to Rounds do
    Sum := Sum + Check(A, Root);
  WriteLn(Sum);
end.
