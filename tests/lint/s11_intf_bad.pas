// EXPECT: error SAFE-S11
{ S11: a field of a task holds an interface. The object behind the reference is shared with the caller, so its state
  is reachable from two threads; the task should take a TShared (or TOwned via Move) or a value. }
unit s11_intf_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  ICounter = interface
    function Next: Integer;
  end;

  TWorker = class(TTask)
  public
    Counter: ICounter;
    procedure Run; override;
  end;

implementation

procedure TWorker.Run;
begin
end;

end.
