// EXPECT: clean
{ S11, pointer types of other units: a unit that declares a pointer type in its interface (marked for S4).
  s11_ptr_other_bad uses it; bpvet reads its pointer types because the file lies next to it. }
unit s11_ptr_lib;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TLibNode = record
    Value: Integer;
  end;
  // UNSAFE: nodes of a C list, read only at the boundary
  PLibNode = ^TLibNode;

implementation

end.
