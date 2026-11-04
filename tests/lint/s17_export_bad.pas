// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: an exported routine keeps values of the caller's region in Self without // root: Self (bpvet --fix writes it). }
unit s17_export_bad;
{$mode objfpc}{$H+}
interface
uses Region, Safe;
type
  TF = class(TRegionObject)
    Next: TF;
    procedure Add;
  end;
implementation
procedure TF.Add;
begin
  Next := TF.Create;
end;
end.
