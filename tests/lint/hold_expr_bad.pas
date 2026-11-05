// EXPECT: error SAFE-S6
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the second argument is not a constructor call: an object made elsewhere may have another owner. }
unit hold_expr_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TFoo = class
  public
    X: Integer;
  end;

procedure Run(const Given: TFoo);

implementation

procedure Run(const Given: TFoo);
var
  S: TScopeRef;
  F: TFoo;
begin
  for S in Scope do
  begin
    S.Hold(F, Given);
    F.X := 1;
  end;
end;

end.
