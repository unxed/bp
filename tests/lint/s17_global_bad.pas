// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a value of a region is stored into a global. }
unit s17_global_bad;

{$mode objfpc}{$H+}

interface

uses
  Region, Safe;

type
  TFields = class(TRegionObject)
    Key, Value: String;
    Next: TFields;
  end;
  TList = specialize TGrowArray<TFields>;

threadvar
  Last: TFields;  // borrow: an object of the region of Keep

procedure Keep;

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

procedure Keep;
var
  R: TRegion;
begin
  R := TRegion.Create;
  Last := TFields.Create;
end;

end.
