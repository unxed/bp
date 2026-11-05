// EXPECT: error SAFE-S7
{ S7: BP first in a program is an error as in a unit: SysUtils after it shadows it; tools/bp build adds -FaBPThreads,
  which installs the thread manager first (safe/SPEC.md §24.3), so BP goes last. }
program s07_program_bp;

{$mode objfpc}{$H+}

uses
  BP, SysUtils;

begin
  WriteLn(IntToStr(42));
end.
