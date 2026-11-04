// EXPECT: warn SAFE-S22
{ S22: a reserved word with an upper-case letter. }
unit s22_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

implementation

procedure P;
Begin
end;

end.
