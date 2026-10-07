// EXPECT: fail SAFE-S2
program mf_fillchar;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var A: Integer;
begin
  FillChar(A, SizeOf(A), 0);
end.
