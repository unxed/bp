// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the held object is stored into a global. }
unit hold_escape_global_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TFoo = class
  public
    X: Integer;
  end;

threadvar
  Last: TFoo; // borrow: the last object of Run

procedure Run;

implementation

procedure Run;
var
  S: TScopeRef;
  F: TFoo;
begin
  for S in Scope do
  begin
    S.Hold(F, TFoo.Create);
    Last := F;
  end;
end;

end.
