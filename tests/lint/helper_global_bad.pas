// EXPECT: error SAFE-S19
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A helper method is a method: a write to a global of a unit, in a helper for Integer, is S19 (the typed mode). }
unit helper_global_bad;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

interface

uses
  Safe;

type
  TIntHelper = type helper for Integer
    procedure Remember;
  end;

var
  Last: Integer;

implementation

procedure TIntHelper.Remember;
begin
  Last := Self;
end;

end.
