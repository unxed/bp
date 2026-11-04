// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a value of a region is stored into a field of an object of another style. }
unit s17_heap_bad;

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

  TBox = class
    Item: TFields;  // borrow: an object of the region of the caller
  end;

procedure Put(const B: TBox);

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

procedure Put(const B: TBox);
var
  R: TRegion;
begin
  R := TRegion.Create;
  B.Item := TFields.Create;
end;

end.
