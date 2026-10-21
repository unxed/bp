// EXPECT: error SAFE-S8
{ S11 and a full name: a field System.PChar of a task without a // UNSAFE: mark is already an error of S8 (a full name
  of a poisoned type), so S11 adds no second finding for it; one mark covers both rules. One finding, of S8. }
unit s11_ptrsys_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TWorker = class(TTask)
  public
    Text: System.PChar;
    procedure Run; override;
  end;

implementation

procedure TWorker.Run;
begin
end;

end.
