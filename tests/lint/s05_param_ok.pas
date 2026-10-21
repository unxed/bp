// EXPECT: clean
{ S5, escape of a borrow: a parameter of a class type is used inside the call, goes into a local variable or
  Result, or into a field/global marked // borrow: <who owns it>; a parameter of a value type may be stored. }
unit s05_param_ok;

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
    Cur: TNode; // borrow: the caller keeps the node alive while the view lives
    Count: Integer;
    procedure Show(const ANode: TNode; const ACount: Integer);
  end;

var
  Last: TNode; // borrow: the caller owns it

function Pick(const ANode: TNode): TNode;
procedure Keep(const ANode: TNode);

implementation

procedure TView.Show(const ANode: TNode; const ACount: Integer);
var
  P: TNode;
begin
  P := ANode;
  Count := ACount + P.Value;
  // borrow: the caller keeps ANode alive while the view lives
  Self.Cur := ANode;
end;

function Pick(const ANode: TNode): TNode;
begin
  Result := ANode;
end;

procedure Keep(const ANode: TNode);
begin
  Last := ANode; // borrow: the caller owns it and outlives Last
end;

end.
