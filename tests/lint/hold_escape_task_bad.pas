// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the held object is passed to the constructor of a task, which may run after the scope ends. }
unit hold_escape_task_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TFoo = class
  public
    X: Integer;
  end;

  TWork = class(TTask)
  private
    // UNSAFE: a borrow of the caller's object, so that the Hold check has a task to find
    FFoo: TFoo; // borrow: the caller's object
  public
    constructor Create(const AFoo: TFoo);
    procedure Run; override;
  end;

procedure Start(const G: TGroup);

implementation

constructor TWork.Create(const AFoo: TFoo);
begin
  inherited Create;
  FFoo := AFoo; // borrow: the caller's object
end;

procedure TWork.Run;
begin
  FFoo.X := 1;
end;

procedure Start(const G: TGroup);
var
  S: TScopeRef;
  F: TFoo;
begin
  for S in Scope do
  begin
    S.Hold(F, TFoo.Create);
    G.Go(TWork.Create(F));
  end;
end;

end.
