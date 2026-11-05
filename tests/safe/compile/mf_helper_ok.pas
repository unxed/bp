// EXPECT: run
// FPCOPTS: -FaBPThreads
program mf_helper_ok;
{$mode objfpc}{$H+}
{$modeswitch typehelpers}
{$modeswitch advancedrecords}
uses SysUtils, Safe;
type
  TNode = class
  public
    X: Integer;
  end;

  TNodeBox = specialize TOwned<TNode>;

  TPoint = record
    X, Y: Integer;
  end;

  TIntHelper = type helper for Integer
    function Twice: Integer;
  end;

  { inherits TStringHelper of SysUtils: only one helper is in effect for a type, the last one declared }
  TStrHelper = type helper(TStringHelper) for String
    function Bracketed: String;
  end;

  TPointHelper = record helper for TPoint
    function Sum: Integer;
  end;

  TNodeHelper = class helper for TNode
    function Twice: Integer;
  end;

  TNodeBoxHelper = record helper for TNodeBox
    function Value: Integer;
  end;

  TTagHelper = class helper(TSafeObjectHelper) for TObject
    function Tag: Integer;
  end;

function TIntHelper.Twice: Integer;
begin
  Result := Self * 2;
end;

function TStrHelper.Bracketed: String;
begin
  Result := '[' + Self.Trim + ']';
end;

function TPointHelper.Sum: Integer;
begin
  Result := X + Y;
end;

function TNodeHelper.Twice: Integer;
begin
  Result := X * 2;
end;

function TNodeBoxHelper.Value: Integer;
begin
  Result := Get.X;
end;

function TTagHelper.Tag: Integer;
begin
  Result := 1;
end;

var
  Box: TNodeBox;
  P: TPoint;
  S: String;
begin
  Box := TNodeBox.Own(TNode.Create);
  Box.Get.X := 5;
  P.X := 3;
  P.Y := 4;
  S := '  ab  ';
  if (Box.Value <> 5) or (Box.Get.Twice <> 10) or (P.Sum <> 7) or (Integer(21).Twice <> 42)
    or (S.Bracketed <> '[ab]') or (S.Trim <> 'ab') or (Box.Get.Tag <> 1) then
    Halt(1);
end.
