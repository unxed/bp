// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A character of the String is written while a view of it lives: a map of views would hold changed keys. }
unit s28_index_bad;

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
  Text := Name + 'x';
  W := StrView(Text);
  Text[1] := 'y';
  Result := W.Len;
end;

end.
