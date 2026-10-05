// EXPECT: fail SAFE-S1
program mf_freemem;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var P: System.Pointer = nil;
begin
  FreeMem(P);
end.
