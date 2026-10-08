// EXPECT: exit 232
{ FFI to libc + goroutines without -dSAFE_LIBC: BPThreads must stop the program
  with an explanation (code 232) instead of letting threads call libc without its TLS. Linux only. }
program mf_libc_guard;
{$mode objfpc}{$H+}
uses BP, SysUtils;
function c_getpid: LongInt; cdecl; external 'c' name 'getpid';
procedure Nop; begin end;
var G: TGroup;
begin
  if c_getpid <= 0 then Halt(1);
  G := TGroup.Create;
  G.Go(@Nop);
  G.Wait;
  Halt(0); // must not get here
end.
