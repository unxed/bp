// EXPECT: error SAFE-S11
{ S11: a field of a task holds a borrow. // borrow: satisfies S5, but a task runs on another thread and can outlive
  the caller, so the field is a data race or a use after free; the task should take a TShared (or TOwned via Move). }
unit s11_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TNode = class
  public
    Value: Integer;
  end;

  TWorker = class(TTask)
  public
    Node: TNode; // borrow: the caller keeps the node alive
    procedure Run; override;
  end;

implementation

procedure TWorker.Run;
begin
end;

end.
