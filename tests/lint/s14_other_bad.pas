// EXPECT: error SAFE-S14
// ARGS: -Fu@lint@
unit s14_other_bad;

{$mode objfpc}{$H+}

interface

uses
  s14_lib, Safe;

function F(R: TLibRec): Integer;

implementation

function F(R: TLibRec): Integer;
begin
  Result := R.X;
end;

end.
