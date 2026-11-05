// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the held object is stored into a field of another object, which outlives the scope. }
unit hold_escape_field_bad;

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
    Last: TFoo; // borrow: the last object of Run
  end;

procedure Run(const B: TBox);

implementation

procedure Run(const B: TBox);
var
  S: TScopeRef;
  F: TFoo;
begin
  for S in Scope do
  begin
    S.Hold(F, TFoo.Create);
    B.Last := F;
  end;
end;

end.
