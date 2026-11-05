// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the variable is read after the Release of the region that held the object. }
unit hold_after_release_bad;

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
  R: TRegion;
  F: TFoo;
begin
  R := TRegion.Create;
  R.Hold(F, TFoo.Create);
  F.X := 1;
  R.Release;
  Result := F.X;
end;

end.
