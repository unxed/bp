// EXPECT: exit 232
// UNSAFE-UNIT: the check calls libc directly (FFI without a binding unit) on purpose: BPThreads must stop it
{ FFI to libc + goroutines without -dSAFE_LIBC: BPThreads must stop the program
  with an explanation (code 232) instead of letting threads call libc without its TLS. Linux only. }
program mf_libc_guard;
{$mode objfpc}{$H+}
// UNSAFE: BP goes first for the thread manager (SPEC §14); the check does not free objects by hand
uses BP, SysUtils;
{ The library name is a constant, not the literal 'c': fcl-passrc 3.2.2 (bpvet) does not parse
  external with a one-character string literal. }
const LibC = 'c';
function c_getpid: LongInt; cdecl; external LibC name 'getpid';
procedure Nop; begin end;
var G: TGroup;
begin
  if c_getpid <= 0 then Halt(1);
  G := TGroup.Create;
  G.Go(@Nop);
  G.Wait;
  Halt(0); // must not get here
end.
