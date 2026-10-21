// EXPECT: clean
{ S7: BP is first in the program for the thread manager (safe/SPEC.md §14) and SysUtils after it shadows it, but the
  uses are marked // UNSAFE: <why>, so the warning is a known exception and bpvet reports nothing. }
program s07_program_bp_marked;

{$mode objfpc}{$H+}

// UNSAFE: BP goes first for the thread manager; the program file only calls IntToStr of SysUtils
uses
  BP, SysUtils;

begin
  WriteLn(IntToStr(42));
end.
