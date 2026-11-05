// EXPECT: error SAFE-S25
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S25: the parameter is marked, but TBig(Buf)[N] writes anywhere: the cast is an error of its own (H18). }
unit s25_cast_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TBig = array[0..99999] of Byte;

// UNSAFE: the caller passes a buffer of N bytes
procedure Poke(var Buf; const N: Integer);

implementation

procedure Poke(var Buf; const N: Integer);
begin
  TBig(Buf)[N] := 1;
end;

end.
