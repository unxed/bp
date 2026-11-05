// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Delete from the String while a view of it lives. }
unit s28_delete_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const Name: String): SizeInt;

implementation

function Run(const Name: String): SizeInt;
var
  Text: String;
  W: TStrView;
begin
  Text := Name;
  W := StrView(Text);
  Delete(Text, 1, 1);
  Result := W.Len;
end;

end.
