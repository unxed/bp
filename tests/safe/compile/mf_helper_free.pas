// EXPECT: fail SAFE_S3
program mf_helper_free;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
type
  TNode = class
  end;

  { a helper for a class does not lift the poison of Free: Self.Free still needs the argument that cannot be written }
  TNodeHelper = class helper for TNode
    procedure Drop;
  end;

procedure TNodeHelper.Drop;
begin
  Self.Free;
end;

begin
end.
