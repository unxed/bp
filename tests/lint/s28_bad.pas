// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The String of a view is a temporary: FieldViews(ReadText(Name)) views a String freed after the statement. }
unit s28_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

procedure Run(const Name: String);

implementation

type
  TCounts = specialize TMap<TStrView, Int64>;

function ReadText(const Name: String): String;
begin
  Result := Name + ' a b a';
end;

procedure Run(const Name: String);
var
  W: TStrView;
  M: TCounts;
begin
  for W in FieldViews(ReadText(Name)) do
    Inc(M.Ref(W, 0)^);
end;

end.
