// EXPECT: exit 232
{ FFI к libc + горутины без -dSAFE_LIBC: SafeThreads должен остановить программу
  с объяснением (код 232), а не дать потокам звать libc без её TLS. Только Linux. }
program mf_libc_guard;
{$mode objfpc}{$H+}
uses SafeThreads, SysUtils, Safe;
function c_getpid: LongInt; cdecl; external 'c' name 'getpid';
procedure Nop; begin end;
var G: TGroup;
begin
  if c_getpid <= 0 then Halt(1);
  G := TGroup.Create;
  G.Go(@Nop);
  G.Wait;
  Halt(0); // сюда попадать не должны
end.
