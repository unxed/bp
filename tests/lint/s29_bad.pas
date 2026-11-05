// EXPECT: error SAFE-S29
{ S29: a class helper for TObject takes the place of the TSafeObjectHelper of Safe, so Obj.Free compiles again.
  The file breaks S29 only: one finding. }
unit s29_bad;

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
