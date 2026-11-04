// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: the result is allocated in the region of the routine, which is freed when it returns. }
unit s17_result_bad;

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

function Make: TFields;

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

function Make: TFields;
var
  R: TRegion;
begin
  R := TRegion.Create;
  Result := TFields.Create;
end;

end.
