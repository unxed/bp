// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: a component created with an owner is held by a scope too: two owners (safe/SPEC.md section 21.4). }
unit component_hold_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  {$M+}
  TComponent = class
  public
    constructor Create(const AOwner: TComponent); virtual;
  end;
  {$M-}

  TControl = class(TComponent)
  public
    Caption: String;
  end;

  TButton = class(TControl)
  end;

  TForm = class(TComponent)
  end;

procedure Run(const Form: TForm);

implementation

constructor TComponent.Create(const AOwner: TComponent);
begin
  inherited Create;
end;

procedure Run(const Form: TForm);
var
  S: TScopeRef;
  B: TButton;
begin
  for S in Scope do
  begin
    S.Hold(B, TButton.Create(Form));
    B.Caption := 'OK';
  end;
end;

end.
