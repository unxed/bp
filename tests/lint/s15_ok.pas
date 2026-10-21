// EXPECT: clean
{ S15: a TShared field that does not lead back to its own class is not a cycle; a back reference through TWeak is
  the right way to point up the graph; a cycle the program breaks itself is marked // UNSAFE: <why>. }
unit s15_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TLeaf = class
  public
    Value: Integer;
  end;
  TLeafRef = specialize TShared<TLeaf>;

  TParent = class;
  TParentWeak = specialize TWeak<TParent>;

  TChild = class
  public
    Leaf: TLeafRef;
    Up: TParentWeak;
  end;
  TChildRef = specialize TShared<TChild>;

  TParent = class
  public
    Child: TChildRef;
    Other: specialize TShared<TLeaf>;
  end;

  TRing = class;
  TRingRef = specialize TShared<TRing>;
  TRing = class
  public
    // UNSAFE: Close sets Next to an empty TRingRef before the last owner goes, so the ring never leaks
    Next: TRingRef;
  end;

implementation

end.
