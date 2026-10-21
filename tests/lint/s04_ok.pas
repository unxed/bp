// EXPECT: clean
{ S4: ^T and @ under a // UNSAFE: mark on the line above (one mark covers the block right below it) or at the end
  of the line are allowed; a dereference P^ is not a finding; ^T and @ in a comment or a string are not code. }
unit s04_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  // UNSAFE: a node of an intrusive list that the test never allocates
  PNode = ^TNode;
  TNode = record
    Next: PNode;
    Value: Integer;
  end;
  // UNSAFE: an array of borrowed cells, the cells outlive the array
  TCells = array of ^Integer;

function Peek(const N: TNode): Integer;
procedure Twice(var X: Integer);

implementation

function Peek(const N: TNode): Integer;
begin
  WriteLn('^T and @X are not code here');
  if N.Next <> nil then
    Result := N.Next^.Value
  else
    Result := N.Value;
end;

procedure Twice(var X: Integer);
var
  P: TCells;
begin
  SetLength(P, 1);
  P[0] := @X; // UNSAFE: P is local and dies before X
  P[0]^ := X * 2;
end;

end.
