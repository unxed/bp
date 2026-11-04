// EXPECT: error SAFE-S11m
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11m: a task gets the array of a field of the sender. }
unit s11m_task_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TInts = array of Integer;

  TSum = class(TTask)
  private
    FData: TInts;
  public
    constructor Create(const AData: TInts);
    procedure Run; override;
  end;

  TOwner = class
  private
    FItems: TInts;
  public
    procedure Start(G: TGroup);
  end;

implementation

constructor TSum.Create(const AData: TInts);
begin
  inherited Create;
  FData := AData;
end;

procedure TSum.Run;
begin
end;

procedure TOwner.Start(G: TGroup);
begin
  G.Go(TSum.Create(FItems));
end;

end.
