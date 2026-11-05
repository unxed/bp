// EXPECT: run
// FPCOPTS: -FaBPThreads
{ BP is last in the uses of a program too (SPEC §24.3): -FaBPThreads, which tools/bp build adds, installs the thread
  manager before SysUtils initializes, so a goroutine runs. Without the switch the same order stops the program with
  code 211 (mf_threads_order.pas). }
program mf_bp_last;
{$mode objfpc}{$H+}
uses SysUtils, BP;
var
  Done: LongInt = 0;
  G: TGroup;
procedure Work;
begin
  InterlockedIncrement(Done);
end;
begin
  G := TGroup.Create;
  G.Go(@Work);
  G.Wait;
  if Done <> 1 then
    Halt(1);
end.
