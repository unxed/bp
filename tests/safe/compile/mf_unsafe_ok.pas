// EXPECT: clean
program mf_unsafe_ok;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var
  // UNSAFE: P holds the raw block allocated and freed below
  P: System.Pointer;
  O: TObject; // borrow: the program frees it by hand right below
begin
  // UNSAFE: P is allocated and freed right here
  System.GetMem(P, 16);
  System.FillChar(P^, 16, 0);
  System.FreeMem(P);
  O := TObject.Create; // UNSAFE: freed by hand right here
  // UNSAFE: O is created on the line above and has no other references
  SysUtils.FreeAndNil(O);
end.
