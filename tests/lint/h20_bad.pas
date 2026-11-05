// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ H20 (unxed/bp#207): a nested routine writes the local X of its parent while its const parameter S is bound to X.
  A const parameter does not count the reference, so X := '' frees the bytes S names, and Y takes the block. }
program h20_bad;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

procedure Outer;
var
  X: String;

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

begin
  Outer;
end.
