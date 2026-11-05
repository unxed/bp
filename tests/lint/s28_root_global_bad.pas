// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The String of a view is a global: any routine may write it while the view lives. }
unit s28_root_global_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run: SizeInt;

var
  Text: String;

implementation

function Run: SizeInt;
var
  W: TStrView;
begin
  Result := 0;
  for W in FieldViews(Text) do
    Inc(Result, W.Len);
end;

end.
