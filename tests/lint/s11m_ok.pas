// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11m: arrays go into channels and tasks as copies, fresh values or the last use of a local. }
unit s11m_ok;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TInts = array of Integer;
  TIntsChan = specialize TChan<TInts>;

  TSum = class(TTask)
  private
    FData: TInts;
    FOut: TIntsChan;
  public
    constructor Create(const AData: TInts; const AOut: TIntsChan);
    procedure Run; override;
  end;

procedure Produce(const Ch: TIntsChan; const Src: TInts; G: TGroup);

implementation

constructor TSum.Create(const AData: TInts; const AOut: TIntsChan);
begin
  inherited Create;
  FData := AData;
  FOut := AOut;
end;

procedure TSum.Run;
begin
  FOut.Send(Copy(FData));
end;

function Fresh(const N: Integer): TInts;
begin
  SetLength(Result, N);
end;

procedure Produce(const Ch: TIntsChan; const Src: TInts; G: TGroup);
var
  A, B: TInts;
  I: Integer;
begin
  Ch.Send(Copy(Src));
  Ch.Send(Fresh(3));
  for I := 1 to 3 do
  begin
    SetLength(A, I);
    A[0] := I;
    Ch.Send(A);
  end;
  A := Fresh(2);
  B := Fresh(1);
  G.Go(TSum.Create(B, Ch));
  Ch.Send(A);
end;

end.
