// EXPECT: fail SAFE-S2
program mf_move;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var A, B: Integer;
begin
  A := 1; Move(A, B, SizeOf(A));
end.
