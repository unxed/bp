// EXPECT: clean
{ S11, interfaces of other units: a unit that declares an interface type in its interface. s11_intf_other_bad uses
  it; bpvet reads its interface types because the file lies next to it. }
unit s11_intf_lib;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  ILibCounter = interface
    function Next: Integer;
  end;

implementation

end.
