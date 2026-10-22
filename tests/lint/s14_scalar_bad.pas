// EXPECT: warn SAFE-S14
{ S14: an unchanged scalar parameter by value should be const. }
unit s14_scalar_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function Twice(N: Integer): Integer;

implementation

function Twice(N: Integer): Integer;
begin
  Result := N * 2;
end;

end.
