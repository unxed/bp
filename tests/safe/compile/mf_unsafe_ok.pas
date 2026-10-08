// EXPECT: clean
program mf_unsafe_ok;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var
  P: System.Pointer;
  O: TObject;
begin
  // UNSAFE: P is allocated and freed right here
  System.GetMem(P, 16);
  System.FillChar(P^, 16, 0);
  System.FreeMem(P);
  O := TObject.Create;
  // UNSAFE: O is created on the line above and has no other references
  SysUtils.FreeAndNil(O);
end.
