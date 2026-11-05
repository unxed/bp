// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the variable is read after the loop of its scope, which destroyed the object. }
unit hold_after_scope_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TFoo = class
  public
    X: Integer;
  end;

function Run: Integer;

implementation

function Run: Integer;
var
  S: TScopeRef;
  F: TFoo;
begin
  F := nil;
  for S in Scope do
  begin
    S.Hold(F, TFoo.Create);
    F.X := 1;
  end;
  Result := F.X;
end;

end.
