// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a value is used after Reset of its region. }
unit s17_reset_bad;

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

procedure Loop(const Lines: array of String);

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

procedure Loop(const Lines: array of String);
var
  R: TRegion;
  F: TFields;
  Line: String;
begin
  R := TRegion.Create;
  F := nil;
  for Line in Lines do
  begin
    if F <> nil then
      Emit(F.Key, Line);
    F := TFields.Create;
    F.Key := Line;
    R.Reset;
  end;
end;

end.
