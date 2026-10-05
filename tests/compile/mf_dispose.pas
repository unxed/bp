// EXPECT: fail SAFE-S1
program mf_dispose;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var P: ^Integer = nil;
begin
  Dispose(P);
end.
