// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A task holds a map of views in a field: the task runs on another thread and outlives the routine. }
unit s28_task_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TCounts = specialize TMap<TStrView, Int64>;

  TCount = class(TTask)
  public
    Counts: TCounts;
  end;

function Run: SizeInt;

implementation

function Run: SizeInt;
begin
  Result := 0;
end;

end.
