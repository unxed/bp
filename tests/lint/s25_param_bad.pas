// EXPECT: error SAFE-S25
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S25: an untyped parameter takes a variable of any type and size (H18). }
unit s25_param_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

procedure Poke(var Buf; N: Integer);

implementation

procedure Poke(var Buf; N: Integer);
begin
  if N < 0 then
    N := 0;
end;

end.
