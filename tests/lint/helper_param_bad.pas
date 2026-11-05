// EXPECT: error SAFE-S14
{ A helper method is a method: a String by value in a helper for String is S14. }
unit helper_param_bad;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

interface

uses
  Safe;

type
  TStrHelper = type helper for String
    function Joined(Other: String): String;
  end;

implementation

function TStrHelper.Joined(Other: String): String;
begin
  Result := Self + Other;
end;

end.
