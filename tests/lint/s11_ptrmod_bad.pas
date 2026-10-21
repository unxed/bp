// EXPECT: error SAFE-S11
{ S11: a field of a task has a pointer type of the module (PNode = ^TNode). The type itself is marked for S4; the
  field that hands such a pointer to another thread is S11's business. One finding, of S11. }
unit s11_ptrmod_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TNode = record
    Value: Integer;
  end;
  // UNSAFE: a list of the C library hands out such nodes
  PNode = ^TNode;

  TWorker = class(TTask)
  public
    Node: PNode;
    procedure Run; override;
  end;

implementation

procedure TWorker.Run;
begin
end;

end.
