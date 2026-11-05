// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S30: a unit whose interface routines carry their // raises: marks; raises_ok, raises_less_bad and raises_fix read
  the marks of this unit (it lies next to them). }
unit raises_lib;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Safe;

type
  ELibError = class(Exception);
  EParse = class(ELibError);

function LibParse(const S: String): Integer;  // raises: EParse
procedure LibCheck(const Ok: Boolean);  // raises: ELibError

implementation

function LibParse(const S: String): Integer;
begin
  if S = '' then
    raise EParse.Create('empty');
  Result := Length(S);
end;

procedure LibCheck(const Ok: Boolean);
begin
  if not Ok then
    raise ELibError.Create('check');
end;

end.
