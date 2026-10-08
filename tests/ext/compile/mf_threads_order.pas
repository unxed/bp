// EXPECT: exit 211
{ BP not first in the program uses (SysUtils before it): the thread manager comes too late, and the first goroutine
  stops with an explanation (code 211) instead of a silent race. Linux in the portable mode only. }
program mf_threads_order;
{$mode objfpc}{$H+}
uses SysUtils, BP;
procedure Nop; begin end;
var G: TGroup;
begin
  G := TGroup.Create;
  G.Go(@Nop);
  G.Wait;
end.
