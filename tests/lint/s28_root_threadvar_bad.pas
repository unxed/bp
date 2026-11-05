// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The String of a view is a threadvar: any routine of the thread may write it. }
unit s28_root_threadvar_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run: SizeInt;

threadvar
  Text: String;

implementation

function Run: SizeInt;
begin
  Result := StrView(Text).Len;
end;

end.
