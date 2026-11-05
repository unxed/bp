// EXPECT: error SAFE-S6
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold: the new object is of a class that is not the class of the variable or a descendant of it. }
unit hold_class_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TFoo = class
  public
    X: Integer;
  end;

procedure Run;

implementation

procedure Run;
var
  S: TScopeRef;
  F: TFoo;
begin
  for S in Scope do
  begin
    S.Hold(F, TStringList.Create);
    F.X := 1;
  end;
end;

end.
