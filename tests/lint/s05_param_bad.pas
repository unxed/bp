// EXPECT: error SAFE-S5
{ S5, escape of a borrow: a parameter of a class type is saved into a global variable without // borrow:. The file
  breaks S5 only: one finding (the declaration of Last is marked, the assignment is not). }
unit s05_param_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TNode = class
  public
    Value: Integer;
  end;

var
  Last: TNode; // borrow: the caller owns it

procedure Keep(const ANode: TNode);

implementation

procedure Keep(const ANode: TNode);
begin
  Last := ANode;
end;

end.
