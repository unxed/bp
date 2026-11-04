// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: Break out of for R in Scope (its region would be released late, out of order). }
unit s17_scope_break_bad;

{$mode objfpc}{$H+}

interface

uses
  Region, Safe;

procedure Run(const Lines: array of String);

implementation

procedure Run(const Lines: array of String);
var
  R, I: Integer;
  Line: String;
begin
  for R in Scope do
    for I := 1 to 3 do
      if I = 2 then
        Break;  // a plain loop: allowed
  for Line in Each(Lines) do
    if Line = '' then
      Break;
end;

end.
