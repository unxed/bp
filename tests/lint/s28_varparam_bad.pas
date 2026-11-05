// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A view stored into an out parameter: the caller keeps it after its String is gone. }
unit s28_varparam_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

procedure Run(const Text: String; out W: TStrView);

implementation

procedure Run(const Text: String; out W: TStrView);
var
  Local: String;
begin
  Local := Text + '!';
  W := StrView(Local);
end;

end.
