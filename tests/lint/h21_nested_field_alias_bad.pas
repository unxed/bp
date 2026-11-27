// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fi@root@/safe -Fu@root@/ext -Fi@root@/ext
{ H21 (unxed/bp#218): the same managed field through a nested record path is passed as const and var. }
program h21_nested_field_alias_bad;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

type
  TInner = record
    Name: String;
  end;
  TOuter = record
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
  X: TOuter;

begin
  X.Inner.Name := StringOfChar('a', 20) + IntToStr(Random(9));
  WriteAlias(X.Inner.Name, X.Inner.Name);
end.
