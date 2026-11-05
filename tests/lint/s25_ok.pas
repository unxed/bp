// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S25: typed parameters, and the untyped ones and `absolute` that carry a mark. }
unit s25_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TBig = array[0..99999] of Byte;

procedure Zero(var Buf: Byte; N: Integer);
// UNSAFE: a facade over an RTL routine that takes any variable; N is checked by the callers
procedure Fill(var Buf; N: Integer);
procedure Name(const Items: array of Integer);

implementation

procedure Zero(var Buf: Byte; N: Integer);
begin
  Buf := Byte(N);
end;

procedure Fill(var Buf; N: Integer);
begin
  if N < 0 then
    N := 0;
end;

procedure Name(const Items: array of Integer);
var
  Wide: Int64;
  // UNSAFE: the low half of Wide, read for a hash
  Low: Longint absolute Wide;
begin
  Wide := Length(Items);
  Wide := Low;
end;

end.
