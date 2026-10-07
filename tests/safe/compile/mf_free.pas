// EXPECT: fail SAFE_S3
program mf_free;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var O: TObject;
begin
  O := TObject.Create; O.Free;
end.
