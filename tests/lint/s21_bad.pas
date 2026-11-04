// EXPECT: warn SAFE-S21
{ S21: a reserved word with an upper-case letter. }
unit s21_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

implementation

procedure P;
Begin
end;

end.
