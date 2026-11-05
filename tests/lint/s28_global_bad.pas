// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A view in a global: a global outlives every routine. }
unit s28_global_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run: SizeInt;

var
  Last: TStrView;

implementation

function Run: SizeInt;
begin
  Result := Last.Len;
end;

end.
