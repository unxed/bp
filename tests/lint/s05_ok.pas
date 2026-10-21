// EXPECT: clean
{ S5: a field or a global of a class type holds the object through an owner (TOwned, TShared, TWeak) or an interface,
  or is marked // borrow: <who owns it> (at the end of the line or on the line above); a local variable and a
  parameter of a class type are borrows by design and are not checked. }
unit s05_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TNode = class
  public
    Value: Integer;
    Next: TNode; // borrow: the list that owns every node
  end;
  TNodeBox = specialize TOwned<TNode>;
  TNodeRef = specialize TShared<TNode>;
  TNodeWeak = specialize TWeak<TNode>;

  IThing = interface
  end;

  TTree = class
  public
    Root: TNodeBox;
    Shared: TNodeRef;
    Parent: TNodeWeak;
    Thing: IThing;
    // borrow: Root owns the node under the cursor
    Cursor: TNode;
  end;

var
  Head: TNodeRef;
  Current: TObject; // borrow: Head owns it

function Sum(const N: TNode): Integer;

implementation

function Sum(const N: TNode): Integer;
var
  P: TNode;
begin
  Result := 0;
  P := N;
  while P <> nil do
  begin
    Result := Result + P.Value;
    P := P.Next;
  end;
end;

end.
