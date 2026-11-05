// EXPECT: error SAFE-S30
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S30: Parse calls LibParse and LibCheck of raises_lib, marked EParse and ELibError; its own mark lists EParse only. }
unit raises_less_bad;

{$mode objfpc}{$H+}

interface

uses
  raises_lib, Safe;

function Parse(const S: String): Integer;  // raises: EParse

implementation

function Parse(const S: String): Integer;
begin
  LibCheck(S <> '-');
  Result := LibParse(S);
end;

end.
