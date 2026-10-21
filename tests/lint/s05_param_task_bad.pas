// EXPECT: error SAFE-S5
{ S5, escape of a borrow into a task: the constructor of a TTask descendant saves a parameter of a class type into a
  field of the task without // borrow:. A task runs on another thread and can outlive the caller, so its arguments
  must be owners (TShared, TOwned via Move), not borrows (safe/SPEC.md §14). The file breaks S5 only: one finding
  (the declaration of FNode is marked, the assignment is not). }
unit s05_param_task_bad;

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
  private
    FNode: TNode; // borrow: the caller keeps the node alive
  public
    constructor Create(const ANode: TNode);
    procedure Run; override;
  end;

implementation

constructor TWorker.Create(const ANode: TNode);
begin
  inherited Create;
  FNode := ANode;
end;

procedure TWorker.Run;
begin
end;

end.
