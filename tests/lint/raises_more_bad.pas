// EXPECT: error SAFE-S30
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S30: the mark of Port lists EStale, which its code no longer raises (only StrToInt raises, EConvertError): a mark
  that lists more than the code raises is wrong too. }
unit raises_more_bad;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Safe;

type
  EStale = class(Exception);

function Port(const S: String): Integer;  // raises: EConvertError, EStale

implementation

function Port(const S: String): Integer;
begin
  Result := StrToInt(S);
end;

end.
