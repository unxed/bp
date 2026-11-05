// EXPECT: error SAFE-S29
{ S29: a helper for a name that is TObject itself is a helper for TObject. }
unit s29_alias_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TAnything = TObject;
  TAnythingTwice = TAnything;

  TAnyHelper = class helper for TAnythingTwice
    function Tag: Integer;
  end;

implementation

function TAnyHelper.Tag: Integer;
begin
  Result := 1;
end;

end.
