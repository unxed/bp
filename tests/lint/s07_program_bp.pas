// EXPECT: warn SAFE-S7
{ S7: BP is first in the program for the thread manager (safe/SPEC.md §14), and SysUtils after it shadows it
  in this file. }
program s07_program_bp;

{$mode objfpc}{$H+}

uses
  BP, SysUtils;

begin
  WriteLn(IntToStr(42));
end.
