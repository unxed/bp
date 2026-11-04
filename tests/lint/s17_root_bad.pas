// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a routine with two region parameters does not name the root of its result (rule 4). }
unit s17_root_bad;

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

function Pick(var A, B: TRegion; const X: TFields): TFields;

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

function Pick(var A, B: TRegion; const X: TFields): TFields;
begin
  A.Reset;
  B.Reset;
  Result := X;
end;

end.
