// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S19: the main block and the routines no task reaches use the globals of the program; a task gets its values. }
program s19_prog_ok;

{$mode objfpc}{$H+}

uses
  BP;

type
  TIntChan = specialize TChan<Integer>;

  TWorker = class(TTask)
  private
    FN: Integer;
    FOut: TIntChan;
  public
    constructor Create(const AN: Integer; const AOut: TIntChan);
    procedure Run; override;
  end;

var
  Limit: Integer;
  Total: Integer;

function Square(const N: Integer): Integer;
begin
  Result := N * N;
end;

procedure Report;
begin
  WriteLn(Total);
end;

constructor TWorker.Create(const AN: Integer; const AOut: TIntChan);
begin
  inherited Create;
  FN := AN;
  FOut := AOut;
end;

procedure TWorker.Run;
begin
  FOut.Send(Square(FN));
end;

procedure Main;
var
  G: TGroup;
  Ch: TIntChan;
  I, V: Integer;
begin
  Ch := TIntChan.Create(Limit);
  G := TGroup.Create;
  for I := 1 to Limit do
    G.Go(TWorker.Create(I, Ch));
  G.Wait;
  for I := 1 to Limit do
    if Ch.Recv(V) then
      Total := Total + V;
  Report;
end;

begin
  Limit := 3;
  Total := 0;
  Main;
end.
