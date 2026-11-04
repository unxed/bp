// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: an object of an iteration of Each kept in an outer local and used after the loop. }
unit s17_loop_bad;

{$mode objfpc}{$H+}

interface

uses
  Region, Safe;

type
  TNamed = class(TRegionObject)
    Name: String;
  end;

procedure Run(const Lines: array of String);

implementation

procedure Run(const Lines: array of String);
var
  R: TRegion;
  Line, Last: String;
  N, Keep: TNamed;
begin
  R := TRegion.Create;
  Keep := TNamed.Create;
  Last := '';
  for Line in Each(Lines) do
  begin
    N := TNamed.Create;
    N.Name := Line;
    Keep := N;
  end;
  WriteLn(Last, Keep.Name);
end;

end.
