// EXPECT: error SAFE-S7
{ S7 (register H9 of safe/SPEC.md): Classes and SysUtils come after Safe and shadow it, so in this program
  FreeAndNil of SysUtils would compile. The file breaks S7 only: one finding. }
program s07_bad;

{$mode objfpc}{$H+}

uses
  Safe, Classes, SysUtils;

begin
  WriteLn(IntToStr(42));
end.
