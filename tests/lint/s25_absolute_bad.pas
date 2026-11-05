// EXPECT: error SAFE-S25
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S25: absolute puts a variable of another type on the memory of the first. }
unit s25_absolute_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function Low32(const Wide: Int64): Longint;

implementation

function Low32(const Wide: Int64): Longint;
var
  W: Int64;
  Half: Longint absolute W;
begin
  W := Wide;
  Result := Half;
end;

end.
