// EXPECT: error SAFE-S12
{ S12: an external declaration in a module that is not marked // UNSAFE-UNIT: (not a binding module).
  The file breaks S12 only: one finding. }
unit s12_bad;

{$mode objfpc}{$H+}

interface

function ProcessId: LongInt;

implementation

uses
  Safe;

const
  LibC = 'c';

function c_getpid: LongInt; cdecl; external LibC name 'getpid';

function ProcessId: LongInt;
begin
  Result := c_getpid;
end;

end.
