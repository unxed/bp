// EXPECT: error SAFE-S5
{ S5, escape of a borrow: a method saves the result of .Get into a field of Self without // borrow:. The file
  breaks S5 only: one finding (the declaration of Cur is marked, the assignment is not). }
unit s05_get_field_bad;

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
    Cur: TNode; // borrow: the caller keeps the owner alive
    procedure Focus(const Box: TNodeBox);
  end;

implementation

procedure TView.Focus(const Box: TNodeBox);
begin
  Self.Cur := Box.Get;
end;

end.
