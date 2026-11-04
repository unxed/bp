// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a nested routine reads and writes the locals of the routine it is in; FPC 3.2 has no block scopes, so a nested
  routine is how a loop gets a region per iteration (safe/SPEC.md §20). }
unit s17_nested_ok;

{$mode objfpc}{$H+}

interface

uses
  Region, Safe;

type
  TFields = class(TRegionObject)
    Key, Value: String;
  end;
  TList = specialize TGrowArray<TFields>;

procedure Collect(const Lines: array of String);

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

procedure Collect(const Lines: array of String);
var
  R: TRegion;
  All: TList;
  Last: TFields;
  Line: String;

  procedure Keep(const S: String);
  var
    F: TFields;
  begin
    F := TFields.Create;  // in R: the current region of the caller
    F.Key := S;
    All.Push(F);
    Last := F;
  end;

  procedure Scratch(const S: String);
  var
    Tmp: TRegion;
    F: TFields;
  begin
    Tmp := TRegion.Create;
    F := TFields.Create;
    F.Key := S;
    Emit(F.Key, Last.Key);
  end;

begin
  R := TRegion.Create;
  All := TList.Create;
  Last := nil;
  for Line in Lines do
  begin
    Keep(Line);
    Scratch(Line);
  end;
  Emit(Last.Key, All[0].Key);
end;

end.
