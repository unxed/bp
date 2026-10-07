// EXPECT: warn SAFE-S4
program mf_pointer;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var P: Pointer;
begin
  P := nil; if P = nil then ;
end.
