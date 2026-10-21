// EXPECT: error SAFE-S14
{ S14: a parameter of a dynamic array type of the module by value. The file breaks S14 only: one finding. }
unit s14_dynarray_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TInts = array of Integer;

function Sum(Values: TInts): Integer;

implementation

function Sum(Values: TInts): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Values) do
    Result := Result + Values[I];
end;

end.
