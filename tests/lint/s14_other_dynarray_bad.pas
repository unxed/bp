// EXPECT: error SAFE-S14
// ARGS: -Fu@lint@
unit s14_other_dynarray_bad;

{$mode objfpc}{$H+}

interface

uses
  s14_lib, Safe;

function F(Values: TLibInts): Integer;

implementation

function F(Values: TLibInts): Integer;
begin
  Result := Length(Values);
end;

end.
