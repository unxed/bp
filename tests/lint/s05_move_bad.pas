// EXPECT: error SAFE-S5
{ S5, Move of an owner while a borrow from it is alive: P := Box.Get, then Box.Move hands the object to another
  owner, which can free it, and P is used after it. The file breaks S5 only: one finding. }
unit s05_move_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TNode = class
  public
    Value: Integer;
  end;
  TNodeBox = specialize TOwned<TNode>;

function Handed(var Box: TNodeBox; out Taken: TNodeBox): Integer;

implementation

function Handed(var Box: TNodeBox; out Taken: TNodeBox): Integer;
var
  P: TNode;
begin
  P := Box.Get;
  Taken := Box.Move;
  Result := P.Value;
end;

end.
