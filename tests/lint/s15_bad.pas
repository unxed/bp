// EXPECT: warn SAFE-S15
{ S15: a class holds an object of its own class through TShared (a list node that owns the next one through a
  shared counter): two nodes pointing at each other never reach zero and leak. }
unit s15_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TNode = class;
  TNodeRef = specialize TShared<TNode>;
  TNode = class
  public
    Value: Integer;
    Next: TNodeRef;
  end;

implementation

end.
