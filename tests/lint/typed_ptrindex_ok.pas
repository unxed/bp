// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
// UNSAFE-UNIT: writes raw blocks through typed pointers
{ Typed mode, #203: an element of a typed pointer is written by index (pointer math of ObjFPC), through a variable and
  through a cast. }
unit typed_ptrindex_ok;

{$mode objfpc}{$H+}

interface

procedure Fill(P: System.Pointer; Size: PtrUInt; V: Byte);
procedure Clear(P: System.Pointer; Count: PtrUInt);

implementation

procedure Fill(P: System.Pointer; Size: PtrUInt; V: Byte);
var
  B: System.PByte;
  I: PtrUInt;
begin
  B := System.PByte(P);
  for I := 0 to Size - 1 do
    B[I] := V;
end;

procedure Clear(P: System.Pointer; Count: PtrUInt);
var
  I: PtrUInt;
begin
  for I := 0 to Count - 1 do
    System.PPtrUInt(P)[I] := 0;
end;

end.
