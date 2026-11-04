// EXPECT: error SAFE-S19
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S19: a var argument writes a global. }
unit s19_var_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

procedure Run;

implementation

var
  Names: array of String;

procedure Add(var L: Integer);
begin
  L := L + 1;
end;

var
  Total: Integer;

procedure Run;
begin
  Add(Total);
end;

initialization
  SetLength(Names, 1);
end.
