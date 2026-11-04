// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a value is used after Release of its region. }
unit s17_release_bad;

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

procedure Done;

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

procedure Done;
var
  R: TRegion;
  F: TFields;
begin
  R := TRegion.Create;
  F := TFields.Create;
  R.Release;
  Emit(F.Key, F.Value);
end;

end.
