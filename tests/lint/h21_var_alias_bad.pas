// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ H21 (unxed/bp#218): the same managed place passed as const and var is uncounted. }
program h21_var_alias_bad;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

procedure WriteAlias(var A: String; const S: String);
var
  Y: String;
begin
  A := '';
  Y := StringOfChar('#', 20) + IntToStr(Random(9));
  WriteLn('S = ', S);
  if Y = '' then
    WriteLn;
end;

var
  X: String;

begin
  X := StringOfChar('a', 20) + IntToStr(Random(9));
  WriteAlias(X, X);
end.
