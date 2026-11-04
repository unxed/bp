// EXPECT: error SAFE-S11s
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11s: a task shares an object that a method writes. }
unit s11s_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TStats = class
  private
    FCount: Integer;
  public
    procedure Add;
  end;

  TSharedStats = specialize TShared<TStats>;

  TWorker = class(TTask)
  private
    FStats: TSharedStats;
  public
    procedure Run; override;
  end;

implementation

procedure TStats.Add;
begin
  Inc(FCount);
end;

procedure TWorker.Run;
begin
  FStats.Get.Add;
end;

end.
