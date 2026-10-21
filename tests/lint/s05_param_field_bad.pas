// EXPECT: error SAFE-S5
{ S5, escape of a borrow: a method saves a parameter of a class type into a field of Self without // borrow:. The
  file breaks S5 only: one finding (the declaration of Cur is marked, the assignment is not). }
unit s05_param_field_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TNode = class
  public
    Value: Integer;
  end;

  TView = class
  public
    Cur: TNode; // borrow: the caller keeps the node alive
    procedure Show(ANode: TNode);
  end;

implementation

procedure TView.Show(ANode: TNode);
begin
  Self.Cur := ANode;
end;

end.
