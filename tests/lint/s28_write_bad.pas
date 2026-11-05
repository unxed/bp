// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The String is assigned while a view of it lives: the view would read freed bytes. }
unit s28_write_bad;

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
  Text := 'other';
  Result := W.Len + Length(Text);
end;

end.
