// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S26b: a class of almost 64 KiB, and a large buffer in a dynamic array. }
unit s26b_ok;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TNear = class
  public
    Buf: array[0..60000] of Byte;
  end;

  TLarge = class
  public
    Buf: array of Byte;
  end;

implementation

end.
