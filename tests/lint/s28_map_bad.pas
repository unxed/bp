// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A map of views in a var parameter gets a view of a local String: the map outlives it. }
unit s28_map_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TCounts = specialize TMap<TStrView, Int64>;

procedure Run(const Name: String; var M: TCounts);

implementation

procedure Run(const Name: String; var M: TCounts);
var
  Text: String;
  W: TStrView;
begin
  Text := Name + ' a b';
  for W in FieldViews(Text) do
    Inc(M.Ref(W, 0)^);
end;

end.
