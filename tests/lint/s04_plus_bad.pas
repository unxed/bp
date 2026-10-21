// EXPECT: error SAFE-S4
{ S4: pointer arithmetic P + N without a // UNSAFE: mark. The file breaks S4 only: one finding. }
unit s04_plus_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function Skip(P: PAnsiChar; N: Integer): PAnsiChar;

implementation

function Skip(P: PAnsiChar; N: Integer): PAnsiChar;
begin
  Result := P + N;
end;

end.
