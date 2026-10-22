// EXPECT: clean
unit s16_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

implementation

// UNSAFE: this fixture documents the opt-out for a module that requires wrapping arithmetic
{$R-}

end.
