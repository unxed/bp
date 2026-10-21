// EXPECT: clean
{ S13: a case over an enumeration of the module lists every value and has no else; a case over an Integer may have
  else; a case with a // UNSAFE: mark may skip values. }
unit s13_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TColor = (clRed, clGreen, clBlue);

function ColorName(const C: TColor): String;
function Small(const N: Integer): Boolean;
function IsRed(const C: TColor): Boolean;

implementation

function ColorName(const C: TColor): String;
begin
  case C of
    clRed: Result := 'red';
    clGreen, clBlue: Result := 'other';
  end;
end;

function Small(const N: Integer): Boolean;
begin
  case N of
    0, 1, 2: Result := True;
  else
    Result := False;
  end;
end;

function IsRed(const C: TColor): Boolean;
begin
  Result := False;
  // UNSAFE: only red matters here, a new color is not red
  case C of
    clRed: Result := True;
  end;
end;

end.
