// EXPECT: error SAFE-S26a
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S26a: an out parameter of a class type is never assigned. }
unit s26a_out_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TFoo = class
  public
    X: Integer;

  end;

procedure Find(out F: TFoo);

implementation

procedure Find(out F: TFoo);
begin
end;

end.
