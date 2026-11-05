// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A function returns a view but has no String parameter it could be a view of. }
unit s28_noparam_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const N: SizeInt): TStrView;

implementation

function Run(const N: SizeInt): TStrView;
begin
  Result := StrView('');
  if N > 0 then
    Result := StrView('x');
end;

end.
