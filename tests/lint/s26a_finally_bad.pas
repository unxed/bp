// EXPECT: error SAFE-S26a
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S26a: the finally block reads a local that the try block assigns: an exception before it leaves garbage. }
unit s26a_finally_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TFoo = class
  public
    X: Integer;

  end;

function Get(const G: TFoo): Integer;

implementation

function Get(const G: TFoo): Integer;
var
  F: TFoo;
begin
  try
    F := G;
    Result := F.X;
  finally
    Result := Ord(F = nil);
  end;
end;

end.
