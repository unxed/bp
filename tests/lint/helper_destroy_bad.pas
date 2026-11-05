// EXPECT: error SAFE-S3
{ A helper method is a method: Self.Destroy in a class helper is S3 (Free does not compile there, S3 of the compiler). }
unit helper_destroy_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TNode = class
  public
    X: Integer;
  end;

  TNodeHelper = class helper for TNode
    procedure Drop;
  end;

implementation

procedure TNodeHelper.Drop;
begin
  Self.Destroy;
end;

end.
