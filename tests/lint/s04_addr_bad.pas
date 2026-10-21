// EXPECT: error SAFE-S4
{ S4: the address operator @ without a // UNSAFE: mark. The file breaks S4 only: one finding. }
unit s04_addr_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

procedure Bump;

implementation

procedure Bump;
var
  X: Integer;
  Addr: PtrUInt;
begin
  X := 1;
  Addr := PtrUInt(@X);
  WriteLn(Addr);
end;

end.
