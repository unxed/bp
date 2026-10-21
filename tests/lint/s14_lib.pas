// EXPECT: clean
// UNSAFE-UNIT: support unit for S14 imported-type lint fixtures
unit s14_lib;

{$mode objfpc}{$H+}

interface

type
  TLibRec = record
    X: Integer;
  end;
  TLibPacked = packed record
    X: Integer;
  end;
  TLibInts = array of Integer;
  TLibFixed = array[0..3] of Integer;

implementation

end.
