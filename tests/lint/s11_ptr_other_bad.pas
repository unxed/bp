// EXPECT: error SAFE-S11
{ S11, a pointer type of another unit (s11_ptr_lib, next to this file) in a field of a task. The memory behind the
  pointer has no owner and is shared with the caller. One finding, of S11. }
unit s11_ptr_other_bad;

{$mode objfpc}{$H+}

interface

uses
  s11_ptr_lib, BP;

type
  TWorker = class(TTask)
  public
    Node: PLibNode;
    procedure Run; override;
  end;

implementation

procedure TWorker.Run;
begin
end;

end.
