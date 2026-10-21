// EXPECT: error SAFE-S4
{ S11 and pointers: a field ^T of a task without a // UNSAFE: mark is already an error of S4 (a raw pointer type),
  so S11 adds no rule of its own for it. One finding, of S4. }
unit s11_ptr_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TWorker = class(TTask)
  public
    Count: ^Integer;
    procedure Run; override;
  end;

implementation

procedure TWorker.Run;
begin
end;

end.
