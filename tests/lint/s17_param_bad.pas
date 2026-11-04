// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: an object of the caller's current region is stored into an object of a parameter, which may be in an outer region. }
unit s17_param_bad;

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

procedure Attach(const Parent: TFields);

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

procedure Attach(const Parent: TFields);
begin
  Parent.Next := TFields.Create;
end;

end.
