// EXPECT: error SAFE-S28
{ S28: a helper for a name that is TObject itself is a helper for TObject. }
unit s28_alias_bad;

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
