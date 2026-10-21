// EXPECT: error SAFE-S13
{ S13: a case over an enumeration of the module does not list clBlue. The file breaks S13 only: one finding. }
unit s13_bad;

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
  Result := '';
  case C of
    clRed: Result := 'red';
    clGreen: Result := 'green';
  end;
end;

end.
