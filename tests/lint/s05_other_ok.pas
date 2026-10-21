// EXPECT: clean
{ S5, a class of another unit (s05_lib, next to this file): held through TOwned, or as a field marked
  // borrow: <who owns it>. }
unit s05_other_ok;

{$mode objfpc}{$H+}

interface

uses
  s05_lib, Safe;

type
  TLibNodeBox = specialize TOwned<TLibNode>;

  TView = class
  public
    Box: TLibNodeBox;
    Cur: TLibNode; // borrow: Box owns it
  end;

var
  Kind: TLibNodeClass;

implementation

end.
