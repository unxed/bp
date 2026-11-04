// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a TRegion global (a region is a local of a routine). }
unit s17_global_region_bad;
{$mode objfpc}{$H+}
interface
uses Region, Safe;
type
  TF = class(TRegionObject)
    Next: TF;
    procedure Add;  // root: Self
  end;
procedure Link(const A, B: TF);  // root: A, B
var
  G: TRegion;
implementation
procedure TF.Add;
begin
  Next := TF.Create;
end;
procedure Link(const A, B: TF);
begin
  A.Next := B;
end;
end.
