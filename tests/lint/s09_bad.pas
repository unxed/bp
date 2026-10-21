// EXPECT: error SAFE-S9
{ S9: a legacy string type outside unsafe code, without a mark. The file breaks S9 only: one finding. }
unit s09_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function Wide(const S: String): Integer;

implementation

function Wide(const S: String): Integer;
var
  U: UnicodeString;
begin
  U := S;
  Result := Length(U);
end;

end.
