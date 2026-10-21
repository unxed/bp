// EXPECT: clean
{ S9: String is the string type of the safe dialect. UnicodeString, WideString and ShortString in comments and
  string literals are not code; a conversion for a UTF-16 API is marked // UNSAFE: (one mark covers the block of
  lines right below it, or it stands at the end of the line). }
unit s09_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TName = record
    Text: String;
  end;

function Utf16Length(const S: String): Integer;
function Describe: String;

implementation

function Utf16Length(const S: String): Integer;
var
  // UNSAFE: the UTF-16 length is what the Windows API counts
  U: UnicodeString;
  W: WideString; // UNSAFE: the same text for a COM BSTR
begin
  // UNSAFE: conversion to UTF-16 for the length the API expects
  U := UnicodeString(S);
  W := U;
  Result := Length(W);
end;

function Describe: String;
var
  MyString: String;
begin
  { ShortString is cut at 255 bytes (* WideString *) }
  MyString := 'UnicodeString, WideString and ShortString are legacy';
  Result := MyString;
end;

end.
