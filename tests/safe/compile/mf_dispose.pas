// EXPECT: fail SAFE-S1
program mf_dispose;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
// UNSAFE: this check must fail on Dispose (SAFE-S1); the raw pointer is the point of the test
var P: ^Integer = nil;
begin
  Dispose(P);
end.
