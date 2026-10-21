// EXPECT: clean
{ S11: the fields of a task are owners, values, String, TArray or TChan; a class field of a class that is not a task
  is S5's business; a borrow in a task that the program keeps alive itself is marked // UNSAFE: <why>. }
unit s11_ok;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TNode = class
  public
    Value: Integer;
  end;
  TNodeRef = specialize TShared<TNode>;

  TWorker = class(TTask)
  public
    Node: TNodeRef;
    Name: String;
    Count: Integer;
    procedure Run; override;
  end;

  TSubWorker = class(TWorker)
  public
    // UNSAFE: the group of the caller waits for the task before the node goes
    Peer: TNode; // borrow: the caller keeps the node alive
    Buf: PChar; // UNSAFE: the buffer is a constant string literal of the program
  end;

  THolder = class
  public
    Node: TNode; // borrow: the list that owns every node
  end;

implementation

procedure TWorker.Run;
begin
end;

end.
