// EXPECT: fail does not seem to be initialized
// FPCOPTS: -Sew
{ H19: an uninitialised local of a class type is a garbage pointer, not nil. FPC warns, and -Sew, which tools/bp build
  adds, makes the warning an error (SPEC §24.6). }
program mf_uninit;
{$mode objfpc}{$H+}
uses Safe;
type
  TFoo = class
    X: Integer;
  end;
procedure Show;
var
  F: TFoo; // borrow: never assigned, which is the subject of this check
begin
  WriteLn(F.X);
end;
begin
  Show;
end.
