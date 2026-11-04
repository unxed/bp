// EXPECT: error SAFE-S11m
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11m: the sender writes the array after it sent it. }
unit s11m_after_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TInts = array of Integer;
  TIntsChan = specialize TChan<TInts>;

procedure Fill(const Ch: TIntsChan);

implementation

procedure Fill(const Ch: TIntsChan);
var
  A: TInts;
begin
  SetLength(A, 2);
  Ch.Send(A);
  A[0] := 1;
end;

end.
