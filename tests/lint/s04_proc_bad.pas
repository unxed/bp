// EXPECT: error SAFE-S4
{ S4: @ of a procedure of the module is not a finding, @ of a variable on the same line still is. The file breaks
  S4 only: one finding. }
unit s04_proc_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TCallback = procedure;

procedure Run;

implementation

procedure Tick;
begin
end;

procedure Keep(const P: TCallback; const Addr: PtrUInt);
begin
  P();
  WriteLn(Addr);
end;

procedure Run;
var
  X: Integer;
begin
  X := 1;
  Keep(@Tick, PtrUInt(@X));
end;

end.
