// EXPECT: error SAFE-S19
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S19: a routine that a task reaches through a call and an override names a global of the program. }
program s19_prog_bad;

{$mode objfpc}{$H+}

uses
  BP;

type
  TWorker = class(TTask)
  protected
    procedure Make; virtual;
  public
    procedure Run; override;
  end;

  TBigWorker = class(TWorker)
  protected
    procedure Make; override;
  end;

var
  Total: Integer;

procedure TWorker.Make;
begin
end;

procedure TBigWorker.Make;
begin
  Inc(Total);
end;

procedure TWorker.Run;
begin
  Make;
end;

procedure Main;
var
  G: TGroup;
begin
  G := TGroup.Create;
  G.Go(TBigWorker.Create);
  G.Wait;
end;

begin
  Total := 0;
  Main;
  WriteLn(Total);
end.
