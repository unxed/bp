// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Extension methods (SPEC §24.4): a helper for a primitive type, a record, a class and an owner type of Safe, written
  with the public methods of the type, is plain code for every rule. Class helpers need no modeswitch, a type helper
  needs typehelpers, a record helper needs advancedrecords as well. }
unit helper_ok;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}
{$modeswitch advancedrecords}

interface

uses
  Safe;

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
    function Clamped(const Lo, Hi: Integer): Integer;
  end;

  TStrHelper = type helper for String
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

function Use(const B: TNodeBox; const P: TPoint): Integer;

implementation

function TIntHelper.Twice: Integer;
begin
  Result := Self * 2;
end;

function TIntHelper.Clamped(const Lo, Hi: Integer): Integer;
begin
  if Self < Lo then
    Result := Lo
  else if Self > Hi then
    Result := Hi
  else
    Result := Self;
end;

function TStrHelper.Bracketed: String;
begin
  Result := '[' + Self + ']';
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

function Use(const B: TNodeBox; const P: TPoint): Integer;
begin
  Result := B.Value + P.Sum + B.Get.Twice + Integer(7).Twice + Length(String('a').Bracketed);
end;

end.
