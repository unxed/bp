// EXPECT: fail SAFE-S1
program mf_getmem;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var P: System.Pointer;
begin
  GetMem(P, 16);
end.
