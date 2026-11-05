// EXPECT: error SAFE-S30
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S30: the handler of Logged takes what Parse raises and raises it again, so Logged raises EParse and needs the mark;
  the handler of Quiet keeps it, so Quiet needs none. }
unit raises_reraise_bad;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, raises_lib, Safe;

function Logged(const S: String): Integer;
function Quiet(const S: String): Integer;

implementation

function Logged(const S: String): Integer;
begin
  try
    Result := LibParse(S);
  except
    on E: Exception do
    begin
      WriteLn(E.Message);
      raise;
    end;
  end;
end;

function Quiet(const S: String): Integer;
begin
  try
    Result := LibParse(S);
  except
    on E: ELibError do
      Result := 0;
  end;
end;

end.
