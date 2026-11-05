// EXPECT: error SAFE-S30
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S30: Load is in the interface and raises ELoad, but its header has no // raises: mark (bpvet --fix writes it). }
unit raises_missing_bad;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Safe;

type
  ELoad = class(Exception);

procedure Load(const Name: String);

implementation

procedure Load(const Name: String);
begin
  if Name = '' then
    raise ELoad.Create('no name');
end;

end.
