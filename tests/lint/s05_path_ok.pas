// EXPECT: clean
// ARGS: -Fu@lint@/units
{ S5, a class of a unit found through -Fu (tests/lint/units/s05_far.pas): held through TOwned, or as a global
  marked // borrow: <who owns it>. }
unit s05_path_ok;

{$mode objfpc}{$H+}

interface

uses
  s05_far, Safe;

type
  TFarNodeBox = specialize TOwned<TFarNode>;

var
  Box: TFarNodeBox;
  Current: TFarNode; // borrow: Box owns it

implementation

end.
