// EXPECT: error SAFE-S13
{ S13: a case over an enumeration of the module has else, which would silently take a new value. The file breaks
  S13 only: one finding. }
unit s13_else_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TColor = (clRed, clGreen, clBlue);

function ColorName(const C: TColor): String;

implementation

function ColorName(const C: TColor): String;
begin
  case C of
    clRed: Result := 'red';
  else
    Result := 'other';
  end;
end;

end.
