// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ H21 (unxed/bp#218): a nested routine writes a global also passed to const. }
program h21_nested_global_write_bad;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

var
  GlobalText: String;

procedure Outer;

  procedure Print(const S: String);
  begin
    GlobalText := '';
    WriteLn('S = ', S);
  end;

begin
  GlobalText := StringOfChar('a', 20) + IntToStr(Random(9));
  Print(GlobalText);
end;

begin
  Outer;
end.
