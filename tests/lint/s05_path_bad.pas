// EXPECT: error SAFE-S5
// ARGS: -Fu@lint@/units
{ S5, a class of a unit found through -Fu (tests/lint/units/s05_far.pas) in a global variable without
  // borrow:. Without -Fu bpvet does not know TFarNode and the file is clean. One finding. }
unit s05_path_bad;

{$mode objfpc}{$H+}

interface

uses
  s05_far, Safe;

var
  Current: TFarNode;

implementation

end.
