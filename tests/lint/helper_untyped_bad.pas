// EXPECT: error SAFE-S25
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A helper method is a method: an untyped parameter, in a helper for Integer, is S25 (the typed mode). }
unit helper_untyped_bad;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

interface

uses
  Safe;

type
  TIntHelper = type helper for Integer
    procedure Store(var Buf);
  end;

implementation

procedure TIntHelper.Store(var Buf);
begin
end;

end.
