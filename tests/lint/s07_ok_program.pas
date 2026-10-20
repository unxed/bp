// EXPECT: clean
{ S7: a program without goroutines ends its uses with BP, as every other module does. }
program s07_ok_program;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

begin
  WriteLn(IntToStr(42));
end.
