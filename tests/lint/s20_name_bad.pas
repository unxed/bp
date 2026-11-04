// EXPECT: error SAFE-S20
{ S20: the name of the unit is not the name of its file (two sources of the name). }
unit Other;

{$mode objfpc}{$H+}

interface

uses
  Safe;

implementation

end.
