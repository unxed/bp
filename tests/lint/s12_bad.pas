// EXPECT: error SAFE-S12
{ S12: an external declaration in a module that is not marked // UNSAFE-UNIT: (not a binding module).
  The file breaks S12 only: one finding. }
unit s12_bad;

{$mode objfpc}{$H+}

interface

function CLength(const S: String): SizeInt;

implementation

const
  LibC = 'c';

function c_strlen(P: PAnsiChar): SizeInt; cdecl; external LibC name 'strlen';

function CLength(const S: String): SizeInt;
begin
  Result := c_strlen(PAnsiChar(S));
end;

end.
