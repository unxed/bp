// EXPECT: clean
{ Why bpvet S7 warns about implementation uses (tests/lint/s07_impl.pas): a unit of the implementation uses comes
  after Safe of the interface and shadows it, so FreeAndNil of SysUtils compiles below. If this check fails with
  SAFE-S3, Safe already wins there and the warning of S7 can go. }
unit mf_s07_impl_shadow;
{$mode objfpc}{$H+}
interface
uses Safe;
procedure Drop;
implementation
// UNSAFE: the shadowing is the subject of this check: FreeAndNil of SysUtils must compile below
uses SysUtils;
procedure Drop;
var O: TObject;
begin
  O := TObject.Create; FreeAndNil(O);
end;
end.
