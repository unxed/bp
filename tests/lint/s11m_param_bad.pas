// EXPECT: error SAFE-S11m
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11m: a const parameter is still held by the caller. }
unit s11m_param_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TInts = array of Integer;
  TIntsChan = specialize TChan<TInts>;

procedure Pass(const Ch: TIntsChan; const Src: TInts);

implementation

procedure Pass(const Ch: TIntsChan; const Src: TInts);
begin
  Ch.Send(Src);
end;

end.
