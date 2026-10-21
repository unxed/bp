// EXPECT: error SAFE-S5
{ S5: a field of a record whose type is a class of the RTL (TStringList), without // borrow:. The file breaks S5
  only: one finding. }
unit s05_field_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TLog = record
    Lines: TStringList;
    Count: Integer;
  end;

implementation

end.
