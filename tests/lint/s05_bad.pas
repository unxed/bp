// EXPECT: error SAFE-S5
{ S5: a global variable of a class declared in the module, without // borrow:, is a borrow that can outlive its
  owner. The file breaks S5 only: one finding. }
unit s05_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TCache = class
  public
    Hits: Integer;
  end;

var
  Cache: TCache;

implementation

end.
