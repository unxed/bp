// EXPECT: fail SAFE-S3
program mf_freeandnil;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var O: TObject; // borrow: the program frees it by hand right below
begin
  O := TObject.Create; FreeAndNil(O); // UNSAFE: freed by hand right here
end.
