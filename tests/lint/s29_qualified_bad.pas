// EXPECT: error SAFE-S29
{ S29: System.TObject is TObject. }
unit s29_qualified_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TAnyHelper = class helper for System.TObject
    function Tag: Integer;
  end;

implementation

function TAnyHelper.Tag: Integer;
begin
  Result := 1;
end;

end.
