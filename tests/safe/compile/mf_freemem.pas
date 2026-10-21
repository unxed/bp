// EXPECT: fail SAFE-S1
program mf_freemem;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
// UNSAFE: this check must fail on FreeMem (SAFE-S1); the raw pointer is the point of the test
var P: System.Pointer = nil;
begin
  FreeMem(P);
end.
