// EXPECT: error SAFE-S6
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the variable is a field, not a local of the routine. }
unit hold_field_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TFoo = class
  public
    X: Integer;
  end;

  TBox = class
  public
    Foo: TFoo; // borrow: held by the scope of Run
    procedure Run;
  end;



implementation

procedure TBox.Run;
var
  S: TScopeRef;
begin
  for S in Scope do
    S.Hold(Foo, TFoo.Create);
end;

end.
