// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The tree of TComponent is an owner (safe/SPEC.md section 21.4), with Classes.TComponent of the RTL: a component
  created with an owner needs no other owner, and a published component field needs no // borrow:. }
unit component_classes_ok;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TPanel = class(TComponent)
  published
    Child: TPanel;
  public
    procedure Fill;
  end;

implementation

procedure TPanel.Fill;
var
  P: TPanel;
begin
  Child := TPanel.Create(Self);
  P := TPanel.Create(Child);
  P.Child := TPanel.Create(P);
end;

end.
