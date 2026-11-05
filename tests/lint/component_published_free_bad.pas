// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: .Free of a published component field: the form owns the component (safe/SPEC.md section 21.4). }
unit component_published_free_bad;

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
  public
    procedure Drop;
  end;

implementation

constructor TComponent.Create(const AOwner: TComponent);
begin
  inherited Create;
end;

procedure TMainForm.Drop;
begin
  Button1.Free;
end;

end.
