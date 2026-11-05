// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A view in a threadvar: it outlives the routine that made it. }
unit s28_threadvar_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const Text: String): SizeInt;

threadvar
  Last: TStrView;

implementation

function Run(const Text: String): SizeInt;
begin
  Last := StrView(Text);
  Result := Last.Len;
end;

end.
