// EXPECT: fail SAFE_S3
program mf_free;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var O: TObject; // borrow: the program frees it by hand right below
begin
  O := TObject.Create; O.Free; // UNSAFE: freed by hand right here
end.
