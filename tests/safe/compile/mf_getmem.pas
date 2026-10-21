// EXPECT: fail SAFE-S1
program mf_getmem;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
// UNSAFE: this check must fail on GetMem (SAFE-S1); the raw pointer is the point of the test
var P: System.Pointer;
begin
  GetMem(P, 16);
end.
