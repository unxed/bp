// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: the // root: marks of the exported routines, as bpvet --fix writes them. }
unit s17_export_ok;
{$mode objfpc}{$H+}
interface
uses Region, Safe;
type
  TF = class(TRegionObject)
    Next: TF;
    procedure Add;  // root: Self
  end;
procedure Link(const A, B: TF);  // root: A, B
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
