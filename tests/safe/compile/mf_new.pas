// EXPECT: fail SAFE-S1
program mf_new;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var P: ^Integer;
begin
  New(P);
end.
