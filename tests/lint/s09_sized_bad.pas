// EXPECT: error SAFE-S9
{ S9: a sized string String[N] is a ShortString (255 bytes at most, cut silently). The file breaks S9 only. }
unit s09_sized_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TName = record
    Text: String[32];
  end;

implementation

end.
