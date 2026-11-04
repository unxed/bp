// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a routine marked // root: P is called with P outside the current region. }
unit s17_bound_bad;

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

procedure Attach(const Parent: TFields);  // root: Parent
procedure Use;

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

procedure Attach(const Parent: TFields);
begin
  Parent.Next := TFields.Create;
end;

procedure Use;
var
  Outer, Inner: TRegion;
  O: TFields;
begin
  Outer := TRegion.Create;
  O := TFields.Create;
  Attach(O);
  Inner := TRegion.Create;
  Attach(O);
  Inner.Release;
  Emit(O.Next.Key, O.Key);
end;

end.
