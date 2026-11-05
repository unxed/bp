// EXPECT: error SAFE-S28
{ S28: a class helper for TObject takes the place of the TSafeObjectHelper of Safe, so Obj.Free compiles again.
  The file breaks S28 only: one finding. }
unit s28_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TAnyHelper = class helper for TObject
    function Tag: Integer;
  end;

implementation

function TAnyHelper.Tag: Integer;
begin
  Result := 1;
end;

end.
