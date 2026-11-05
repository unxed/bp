// EXPECT: error SAFE-S6
{ A helper method is a method: a new object that nobody owns, in a helper of a record, is S6. }
unit helper_create_bad;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Safe;

type
  TNode = class
  public
    X: Integer;
  end;

  TPoint = record
    X: Integer;
  end;

  TPointHelper = record helper for TPoint
    function Node: TNode;
  end;

implementation

function TPointHelper.Node: TNode;
begin
  Result := TNode.Create;
  Result.X := X;
end;

end.
