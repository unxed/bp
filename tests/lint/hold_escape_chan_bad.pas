// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the held object is sent to a channel: it leaves its goroutine and is destroyed when the scope ends. }
unit hold_escape_chan_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TFoo = class
  public
    X: Integer;
  end;
  TFoos = specialize TChan<TFoo>;

procedure Run(const Ch: TFoos);

implementation

procedure Run(const Ch: TFoos);
var
  S: TScopeRef;
  F: TFoo;
begin
  for S in Scope do
  begin
    S.Hold(F, TFoo.Create);
    Ch.Send(F);
  end;
end;

end.
