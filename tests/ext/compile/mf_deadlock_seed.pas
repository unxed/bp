// EXPECT: exit 2
// FPCOPTS: -FaBPThreads
// ENV: BP_SCHED_SEED=1
{ M:N (SPEC §21.3): a task waits on a channel that nobody sends to, and the main thread waits for the task. Every
  goroutine is parked and the main thread is blocked: the main thread, the only carrier, finds nothing to run, prints "all goroutines are asleep" and stops the program with
  exit code 2, as Go does. }
program mf_deadlock_seed;
{$mode objfpc}{$H+}
uses SysUtils, BP;
type
  TIntChan = specialize TChan<Integer>;
var
  Ch: TIntChan;
  G: TGroup;
procedure Stuck;
var
  V: Integer;
begin
  Ch.Recv(V);
end;
begin
  Ch := TIntChan.Create(0);
  G := TGroup.Create;
  G.Go(@Stuck);
  G.Wait;
end.
