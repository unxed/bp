// EXPECT: error SAFE-S5
{ S5, Reset of an owner while a borrow from it is alive: P := Box.Get, then Box.Reset frees the object, and P is
  used after it. The file breaks S5 only: one finding. }
unit s05_reset_bad;

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

function Dangling(var Box: TNodeBox): Integer;

implementation

function Dangling(var Box: TNodeBox): Integer;
var
  P: TNode;
begin
  P := Box.Get;
  Box.Reset;
  Result := P.Value;
end;

end.
