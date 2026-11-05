// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A region object holds a view: the region outlives the routine of its String. }
unit s28_region_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TNode = class(TRegionObject)
  public
    Word: TStrView;
  end;

function Run: SizeInt;

implementation

function Run: SizeInt;
begin
  Result := 0;
end;

end.
