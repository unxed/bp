// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the held object is the result of the function: the caller gets a destroyed object. }
unit hold_escape_result_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TFoo = class
  public
    X: Integer;
  end;

function Make: TFoo;

implementation

function Make: TFoo;
var
  S: TScopeRef;
  F: TFoo;
begin
  Result := nil;
  for S in Scope do
  begin
    S.Hold(F, TFoo.Create);
    Result := F;
  end;
end;

end.
