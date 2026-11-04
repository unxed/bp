// EXPECT: clean
{ S20 and S21 (safe/SPEC.md §0): the header names the file (letter case aside), every reserved word is in lower case;
  a reserved word in a comment, a string or an asm block, an &escaped identifier and String are not checked. }
unit S20_OK;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function Words: String;

implementation

function Words: String;
var
  &Begin: Integer;
begin
  &Begin := 1;
  Result := 'BEGIN END';  // BEGIN in a comment
end;

end.
