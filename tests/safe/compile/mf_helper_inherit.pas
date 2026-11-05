// EXPECT: fail SAFE_S3
program mf_helper_inherit;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
type
  TNode = class
  end;

  { a helper for TObject that inherits TSafeObjectHelper adds methods and keeps the poison of Free (S28 asks for it) }
  TTagHelper = class helper(TSafeObjectHelper) for TObject
    function Tag: Integer;
  end;

function TTagHelper.Tag: Integer;
begin
  Result := 1;
end;

procedure Drop(N: TNode);
begin
  if N.Tag = 1 then
    N.Free;
end;

begin
end.
