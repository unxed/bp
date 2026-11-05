// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The String of a view is a var parameter: the caller may change it while the view lives. }
unit s28_root_var_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(var S: String): SizeInt;

implementation

function Run(var S: String): SizeInt;
begin
  Result := StrView(S).Len;
  S := S + '!';
end;

end.
