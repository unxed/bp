// EXPECT: error SAFE-S12
// UNSAFE-UNIT: binding of strlen from libc
{ S12: a binding module exports a routine that takes a pointer, so the unsafe part leaks into its public API.
  The file breaks S12 only: one finding. }
unit s12_api_bad;

{$mode objfpc}{$H+}

interface

function CLength(P: PAnsiChar): SizeInt;

implementation

const
  LibC = 'c';

function c_strlen(P: PAnsiChar): SizeInt; cdecl; external LibC name 'strlen';

function CLength(P: PAnsiChar): SizeInt;
begin
  Result := c_strlen(P);
end;

end.
