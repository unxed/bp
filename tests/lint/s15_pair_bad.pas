// EXPECT: warn SAFE-S15
{ S15: two classes hold each other through TShared (an owner and an item that points back at it with a strong
  reference); the warning is on the field that is not marked: the back reference should be TWeak. }
unit s15_pair_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TItem = class;
  TOwnerBox = class
  public
    Item: specialize TShared<TItem>;
  end;
  TOwnerBoxRef = specialize TShared<TOwnerBox>;
  TItem = class
  public
    Back: TOwnerBoxRef; // UNSAFE: the test marks this field so that only TOwnerBox.Item is reported
  end;

implementation

end.
