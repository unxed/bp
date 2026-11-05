// EXPECT: error SAFE-S26a
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A helper method is a method: a local class reference that is read before it is assigned, in a helper for Integer,
  is S26a (the typed mode). }
unit helper_nil_bad;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

interface

uses
  Safe;

type
  TNode = class
  public
    X: Integer;
  end;

  TIntHelper = type helper for Integer
    function Peek: Integer;
  end;

implementation

function TIntHelper.Peek: Integer;
var
  N: TNode;
begin
  Result := N.X + Self;
end;

end.
