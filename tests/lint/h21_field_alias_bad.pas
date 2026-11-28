// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ H21 (unxed/bp#218): the same managed record field passed as const and var is uncounted. }
program h21_field_alias_bad;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

type
  TInner = record
    Value: String;
  end;

  TBox = record
    Inner: TInner;
  end;

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
  Box, OtherBox: TBox;

begin
  Box.Inner.Value := StringOfChar('a', 20) + IntToStr(Random(9));
  OtherBox.Inner.Value := StringOfChar('b', 20) + IntToStr(Random(9));
  WriteAlias(Box.Inner.Value, Box.Inner.Value);
  WriteAlias(Box.Inner.Value, OtherBox.Inner.Value);
end.
