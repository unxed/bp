// EXPECT: error SAFE-S5
{ S5, a class of another unit (s05_lib, next to this file) in a global variable without // borrow:. The file
  breaks S5 only: one finding. }
unit s05_other_bad;

{$mode objfpc}{$H+}

interface

uses
  s05_lib, Safe;

var
  Current: TLibNode;

implementation

end.
