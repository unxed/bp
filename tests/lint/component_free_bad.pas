// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: .Free of a component created with an owner: the owner destroys it (safe/SPEC.md section 21.4). FPC
  does not compile .Free with Safe either (S3). }
unit component_free_bad;

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
begin
  B := TButton.Create(Form);
  B.Caption := 'OK';
  B.Free;
end;

end.
