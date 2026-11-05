// EXPECT: error SAFE-S5
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S5: a field of a component class whose type is a component class, outside the published section: it needs
  // borrow: like any class field (safe/SPEC.md section 21.4). }
unit component_field_bad;

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

  TMainForm = class(TForm)
    Button1: TButton;
  private
    FDefault: TButton;
  public
    procedure Setup;
  end;

implementation

constructor TComponent.Create(const AOwner: TComponent);
begin
  inherited Create;
end;

procedure TMainForm.Setup;
begin
  FDefault := TButton.Create(Self);
  FDefault.Caption := Button1.Caption;
end;

end.
