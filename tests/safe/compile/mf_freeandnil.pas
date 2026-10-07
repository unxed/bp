// EXPECT: fail SAFE-S3
program mf_freeandnil;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var O: TObject;
begin
  O := TObject.Create; FreeAndNil(O);
end.
