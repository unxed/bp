// EXPECT: error SAFE-S4
{ A helper method is a method: the address of Self in a helper for a primitive type is S4. }
unit helper_address_bad;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

interface

uses
  Safe;

type
  TIntHelper = type helper for Integer
    function Where: PtrUInt;
  end;

implementation

function TIntHelper.Where: PtrUInt;
begin
  Result := PtrUInt(@Self);
end;

end.
