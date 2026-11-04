// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a var argument that is a field of an object of an outer region gets a value of an inner one. }
unit s17_varfield_bad;
{$mode objfpc}{$H+}{$modeswitch nestedprocvars}
interface
uses Region, Safe;
type
  TF = class(TRegionObject)
    Next: TF;
  end;
  TCb = procedure is nested;
procedure ByVar;
implementation
procedure Make(out X: TF);
begin
  X := TF.Create;
end;

procedure ByVar;
var
  R1, R2: TRegion;
  O: TF;
begin
  R1 := TRegion.Create;
  O := TF.Create;
  R2 := TRegion.Create;
  Make(O.Next);
  R2.Release;
  WriteLn(O.Next <> nil);
end;
end.
