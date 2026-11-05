// EXPECT: error SAFE-S26a
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S26a: a local assigned on one branch only is read after the branch. }
unit s26a_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TFoo = class
  public
    X: Integer;

  end;

function Get(const C: Boolean; const G: TFoo): Integer;

implementation

function Get(const C: Boolean; const G: TFoo): Integer;
var
  F: TFoo;
begin
  if C then
    F := G;
  Result := F.X;
end;

end.
