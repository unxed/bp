// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: values of a region loop used inside it; strings leave it as copies. }
unit s17_loop_ok;

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
    Last := N.Name;
  end;
  WriteLn(Last, Keep.Name);
end;

end.
