// EXPECT: error SAFE-S19
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S19: a routine writes a global of its unit. }
unit s19_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

var
  Count: Integer;

procedure Tick;

implementation

procedure Tick;
begin
  Count := Count + 1;
end;

end.
