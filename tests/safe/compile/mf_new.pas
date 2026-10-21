// EXPECT: fail SAFE-S1
program mf_new;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
// UNSAFE: this check must fail on New (SAFE-S1); the raw pointer is the point of the test
var P: ^Integer;
begin
  New(P);
end.
