// EXPECT: clean
{ S5, escape of a borrow: the result of .Get goes into a local variable or Result, or into a field/global marked
  // borrow: <who owns it> (at the end of the line or on the line above). }
unit s05_get_ok;

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

  TView = class
  public
    Box: TNodeBox;
    Cur: TNode; // borrow: Box owns it
    procedure Focus;
  end;

var
  Head: TNodeBox;
  Current: TNode; // borrow: Head owns it

function First: TNode;
procedure Remember;

implementation

procedure TView.Focus;
begin
  // borrow: Box of the same view owns it
  Self.Cur := Box.Get;
end;

function First: TNode;
var
  P: TNode;
begin
  P := Head.Get;
  Result := P;
end;

procedure Remember;
begin
  Current := Head.Get; // borrow: Head owns it and outlives Current
end;

end.
