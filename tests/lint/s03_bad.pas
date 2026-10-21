// EXPECT: error SAFE-S3
{ S3: a manual .Destroy without a // UNSAFE: mark. The file breaks S3 only: one finding. }
unit s03_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

procedure DropTemp;

implementation

procedure DropTemp;
var
  O: TObject;
begin
  O := TObject.Create;
  O.Destroy;
end;

end.
