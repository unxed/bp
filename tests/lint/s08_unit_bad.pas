// EXPECT: error SAFE-S8
{ S8: a module that uses neither Safe nor BP and is not marked // UNSAFE-UNIT:. The file breaks S8 only:
  one finding. }
unit s08_unit_bad;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function Twice(const N: Integer): String;

implementation

function Twice(const N: Integer): String;
begin
  Result := IntToStr(2 * N);
end;

end.
