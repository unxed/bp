// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The tree of TComponent is an owner (safe/SPEC.md section 21.4), on a form-like unit with a stub of the hierarchy:
  TFoo.Create(AOwner) with an owner that is not nil gives the new component to the owner (no S6), and a published
  field of a component class whose type is a component class needs no // borrow: (no S5). The default section of a
  component class is published too (TPersistent is compiled with M+). }
unit component_ok;

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
    Button2: TButton;
  published
    Button3, Button4: TButton;
  private
    FCount: Integer;
  public
    procedure Setup;
  end;

procedure Build(const Form: TForm);

implementation

constructor TComponent.Create(const AOwner: TComponent);
begin
  inherited Create;
end;

procedure TMainForm.Setup;
var
  B: TButton;
begin
  B := TButton.Create(Self);
  B.Caption := 'OK';
  Button2 := TButton.Create(Self);
  Button2.Caption := B.Caption;
  Self.Button3 := TButton.Create(Self);
  Inc(FCount);
end;

procedure Build(const Form: TForm);
var
  B: TButton;
begin
  B := TButton.Create(Form);
  B.Caption := 'Cancel';
  TControl.Create(B).Caption := 'Label';
end;

end.
