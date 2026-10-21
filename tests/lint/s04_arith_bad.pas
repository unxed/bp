// EXPECT: error SAFE-S4
{ S4: pointer arithmetic Inc(P) without a // UNSAFE: mark. The file breaks S4 only: one finding (Buf^ and
  Dec(Len) are not pointer arithmetic). }
unit s04_arith_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

procedure Wipe(Buf: PByte; Len: Integer);

implementation

procedure Wipe(Buf: PByte; Len: Integer);
begin
  while Len > 0 do
  begin
    Buf^ := 0;
    Inc(Buf);
    Dec(Len);
  end;
end;

end.
