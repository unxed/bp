// EXPECT: error SAFE-S26a
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S26a: the result is assigned on one branch only. }
unit s26a_result_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TFoo = class
  public
    X: Integer;

  end;

function Make(const C: Boolean; const G: TFoo): TFoo;

implementation

function Make(const C: Boolean; const G: TFoo): TFoo;
begin
  if C then
    Result := G;
end;

end.
