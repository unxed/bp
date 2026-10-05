// EXPECT: warn SAFE-S4
program mf_pchar;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var P: PChar;
begin
  P := nil; if P = nil then ;
end.
