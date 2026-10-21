// EXPECT: error SAFE-S11
{ S11, an interface of another unit (s11_intf_lib, next to this file) in a field of a task. The object behind the
  reference is shared with the caller, so its state is reachable from two threads. One finding. }
unit s11_intf_other_bad;

{$mode objfpc}{$H+}

interface

uses
  s11_intf_lib, BP;

type
  TWorker = class(TTask)
  public
    Counter: ILibCounter;
    procedure Run; override;
  end;

implementation

procedure TWorker.Run;
begin
end;

end.
