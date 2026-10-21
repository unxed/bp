// EXPECT: error SAFE-S11
{ S11: a field of a task has a named pointer type of System (PChar). S4 sees ^T, not the name; the memory behind
  the pointer has no owner and is shared with the caller, so the task on another thread reads it while it changes or
  after it is freed. One finding, of S11. }
unit s11_ptrtype_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TWorker = class(TTask)
  public
    Text: PChar;
    procedure Run; override;
  end;

implementation

procedure TWorker.Run;
begin
end;

end.
