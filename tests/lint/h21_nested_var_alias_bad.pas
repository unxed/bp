// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ H21 (unxed/bp#218): a nested routine writes a var parameter of its parent, also passed to const. }
program h21_nested_var_alias_bad;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

procedure Outer(var X: String);

  procedure Print(const S: String);
  var
    Y: String;
  begin
    X := '';
    Y := StringOfChar('#', 20) + IntToStr(Random(9));
    WriteLn('S = ', S);
    if Y = '' then
      WriteLn;
  end;

begin
  X := StringOfChar('a', 20) + IntToStr(Random(9));
  Print(X);
end;

var
  Value: String;

begin
  Outer(Value);
end.
