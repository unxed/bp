// EXPECT: error SAFE-S14
{ S14: an open array parameter by value (the callee gets a copy of the array). The file breaks S14 only: one
  finding. }
unit s14_openarray_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function Sum(Values: array of Integer): Integer;

implementation

function Sum(Values: array of Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Values) do
    Result := Result + Values[I];
end;

end.
