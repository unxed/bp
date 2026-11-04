// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S19: globals of a unit written in initialization, threadvars, atomic and marked writes. }
unit s19_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

var
  Limit: Integer;

threadvar
  Depth: Integer;

procedure Enter;
function Twice: Integer;

implementation

var
  Hits: Integer;
  Calls: Longint;

procedure Enter;
begin
  Inc(Depth);
  InterlockedIncrement(Calls);
  // UNSAFE: a counter for the log, races only lose a hit
  Inc(Hits);
end;

function Twice: Integer;
var
  Local: Integer;
begin
  Local := Limit;
  Result := Local * 2;
end;

initialization
  Limit := 10;
  Hits := 0;
end.
