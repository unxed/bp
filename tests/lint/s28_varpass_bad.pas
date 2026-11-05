// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The String is passed as a var argument while a view of it lives: the callee may write it. }
unit s28_varpass_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const Name: String): SizeInt;

implementation

procedure Grow(var S: String);
begin
  S := S + '!';
end;

function Run(const Name: String): SizeInt;
var
  Text: String;
  W: TStrView;
begin
  Text := Name;
  W := StrView(Text);
  Grow(Text);
  Result := W.Len;
end;

end.
