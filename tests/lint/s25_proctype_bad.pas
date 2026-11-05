// EXPECT: error SAFE-S25
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S25: a procedure type with an untyped parameter. }
unit s25_proctype_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TFiller = procedure(out Dest; N: Integer);

implementation

end.
