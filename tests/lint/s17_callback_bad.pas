// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a nested routine that keeps values of the current region in locals of its parent is taken as a procedure value. }
unit s17_callback_bad;
{$mode objfpc}{$H+}{$modeswitch nestedprocvars}
interface
uses Region, Safe;
type
  TF = class(TRegionObject)
    Next: TF;
  end;
  TCb = procedure is nested;
procedure Outer;
implementation
procedure CallInRegion(const Cb: TCb);
var
  R: TRegion;
begin
  R := TRegion.Create;
  Cb;
end;

procedure Outer;
var
  R: TRegion;
  Keep: TF;
  procedure Fill;
  begin
    Keep := TF.Create;
  end;
begin
  R := TRegion.Create;
  CallInRegion(@Fill);
  WriteLn(Keep <> nil);
end;

end.
