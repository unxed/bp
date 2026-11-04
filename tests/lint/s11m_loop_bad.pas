// EXPECT: error SAFE-S11m
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11m: a loop sends the same array on every iteration. }
unit s11m_loop_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TPoint = record
    X, Y: Integer;
    Tags: array of String;
  end;
  TPointChan = specialize TChan<TPoint>;

procedure Fill(const Ch: TPointChan);

implementation

procedure Fill(const Ch: TPointChan);
var
  P: TPoint;
  I: Integer;
begin
  SetLength(P.Tags, 1);
  for I := 1 to 3 do
  begin
    P.X := I;
    Ch.Send(P);
  end;
end;

end.
