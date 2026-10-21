// EXPECT: clean
{ Why bpvet S7 warns about a program with BP first (tests/lint/s07_program_bp.pas): BP goes first for the thread
  manager (SPEC §14), SysUtils after it shadows it, so FreeAndNil of SysUtils compiles below. }
program mf_s07_bp_first;
{$mode objfpc}{$H+}
// UNSAFE: the shadowing is the subject of this check: FreeAndNil of SysUtils must compile below
uses BP, SysUtils;
var O: TObject;
begin
  O := TObject.Create; FreeAndNil(O); // UNSAFE: freed by hand right here
end.
