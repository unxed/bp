// EXPECT: error SAFE-S4
{ S4: a raw pointer type ^T without a // UNSAFE: mark. The file breaks S4 only: one finding. }
unit s04_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  PCounter = ^Integer;

implementation

end.
