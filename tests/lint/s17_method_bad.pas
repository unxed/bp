// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a value of a region is passed to a method of an object of another style. }
unit s17_method_bad;

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

  TSink = class
    procedure Take(const F: TFields);
  end;

procedure Put(const S: TSink);

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

procedure TSink.Take(const F: TFields);
begin
  Emit(F.Key, F.Value);
end;

procedure Put(const S: TSink);
var
  R: TRegion;
begin
  R := TRegion.Create;
  S.Take(TFields.Create);
end;

end.
