// EXPECT: error SAFE-S5
{ S5, escape of a borrow: the result of .Get is saved into a global variable without // borrow:. The file breaks
  S5 only: one finding (the declaration of Current is marked, the assignment is not). }
unit s05_get_bad;

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

var
  Head: TNodeBox;
  Current: TNode; // borrow: Head owns it

procedure Remember;

implementation

procedure Remember;
begin
  Current := Head.Get;
end;

end.
