// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The String is written in the loop that makes views of it: the map keeps the views of the last round. }
unit s28_loop_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TCounts = specialize TMap<TStrView, Int64>;

function Run(const Name: String): SizeInt;

implementation

function Run(const Name: String): SizeInt;
var
  Line: String;
  W: TStrView;
  M: TCounts;
  I: Integer;
begin
  for I := 1 to 3 do
  begin
    Line := Name + ' a b';
    for W in FieldViews(Line) do
      Inc(M.Ref(W, 0)^);
  end;
  Result := M.Count;
end;

end.
