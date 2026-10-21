{ S5, classes of other units: a unit in another directory than the files that use it (tests/lint/s05_path_ok,
  s05_path_bad); bpvet finds it through -Fu. }
unit s05_far;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TFarNode = class
  public
    Value: Integer;
  end;

implementation

end.
