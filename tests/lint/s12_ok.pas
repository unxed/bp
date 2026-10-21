// EXPECT: clean
// UNSAFE-UNIT: binding of strlen from libc; the facade below takes a String and returns its length
{ S12: the external declaration with a pointer lives in the implementation of a binding module, and its public
  API is a safe facade without pointers. }
unit s12_ok;

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
