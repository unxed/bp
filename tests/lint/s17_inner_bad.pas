// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: an object of an inner region is stored into an object of an outer one. }
unit s17_inner_bad;

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

procedure Nest;

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

procedure Nest;
var
  Outer, Inner: TRegion;
  O: TFields;
begin
  Outer := TRegion.Create;
  O := TFields.Create;
  Inner := TRegion.Create;
  O.Next := TFields.Create;
  Inner.Release;
  Emit(O.Key, O.Value);
end;

end.
