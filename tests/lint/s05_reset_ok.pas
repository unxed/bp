// EXPECT: clean
{ S5, Reset/Move of an owner with a borrow: fine when the borrow P := Box.Get is no longer used after the Reset or
  Move, or is assigned anew before its next use; a marked line is not a finding. }
unit s05_reset_ok;

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

function Done(var Box: TNodeBox): Integer;
function Handed(var Box: TNodeBox): TNodeBox;
function Again(var Box: TNodeBox): Integer;

implementation

function Done(var Box: TNodeBox): Integer;
var
  P: TNode;
begin
  P := Box.Get;
  Result := P.Value;
  Box.Reset;
end;

function Handed(var Box: TNodeBox): TNodeBox;
var
  P: TNode;
begin
  P := Box.Get;
  P.Value := 1;
  Result := Box.Move;
end;

function Again(var Box: TNodeBox): Integer;
var
  P: TNode;
begin
  P := Box.Get;
  P.Value := 2;
  Box.Reset;
  Box := TNodeBox.Own(TNode.Create);
  P := Box.Get;
  Result := P.Value;
end;

end.
