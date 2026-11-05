// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A view sent to a channel: another goroutine gets it while its String may be gone. }
unit s28_chan_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TViews = specialize TChan<TStrView>;

procedure Run(const Text: String; const Ch: TViews);

implementation

procedure Run(const Text: String; const Ch: TViews);
var
  W: TStrView;
begin
  for W in FieldViews(Text) do
    Ch.Send(W);
end;

end.
