// EXPECT: clean
{ S5, classes of other units: a unit that declares classes in its interface. s05_other_ok and s05_other_bad use
  it; bpvet reads its classes because the file lies next to them. }
unit s05_lib;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TLibNode = class
  public
    Value: Integer;
  end;
  TLibNodeClass = class of TLibNode;

implementation

end.
