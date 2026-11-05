// EXPECT: error SAFE-S6
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S6: a line with a component created with an owner and an object that nobody owns keeps the finding of the
  object (safe/SPEC.md section 21.4). }
unit component_mixed_bad;

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
  B: TButton;
  O: TObject;
begin
  B := TButton.Create(Form); O := TObject.Create;
  B.Caption := O.ClassName;
end;

end.
