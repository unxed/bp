// EXPECT: clean
{ S28: a helper for TObject that inherits TSafeObjectHelper keeps the poisoned Free and adds methods; a helper for
  another class needs no mark; a helper for TObject that replaces the poison on purpose says why. }
unit s28_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TNode = class
  public
    X: Integer;
  end;

  TTagHelper = class helper(TSafeObjectHelper) for TObject
    function Tag: Integer;
  end;

  TNodeHelper = class helper for TNode
    function Twice: Integer;
  end;

  // UNSAFE: this unit is the one that frees by hand, the helper gives it back the plain Free
  TFreeHelper = class helper for TObject
    function Alive: Boolean;
  end;

implementation

function TTagHelper.Tag: Integer;
begin
  Result := 1;
end;

function TNodeHelper.Twice: Integer;
begin
  Result := X * 2;
end;

function TFreeHelper.Alive: Boolean;
begin
  Result := Self <> nil;
end;

end.
