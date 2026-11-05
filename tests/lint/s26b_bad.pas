// EXPECT: error SAFE-S26b
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S26b: an instance of a class is larger than 64 KiB. }
unit s26b_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TFoo = class
  public
    X: Integer;
    Buf: array[0..70000] of Byte;
  end;

procedure Touch;

implementation

procedure Touch;
begin
end;

end.
