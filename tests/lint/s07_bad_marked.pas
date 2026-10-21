// EXPECT: error SAFE-S7
{ S7: a mark // UNSAFE: does not cover the error: a unit that comes after Safe in the same uses clause can always
  move before it. The file breaks S7 only: one finding. }
program s07_bad_marked;

{$mode objfpc}{$H+}

// UNSAFE: a mark that bpvet must ignore for this error
uses
  Safe, SysUtils;

begin
  WriteLn(IntToStr(42));
end.
