// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The String of a view is the result of the function, which the caller gets and may change. }
unit s28_root_result_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const S: String): String;

implementation

function Run(const S: String): String;
var
  N: SizeInt;
begin
  Result := S + '!';
  N := StrView(Result).Len;
  if N = 0 then
    Result := '';
end;

end.
