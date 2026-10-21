// EXPECT: clean
{ S3: a destructor declaration, its heading and inherited Destroy are not calls; a call .Destroy marked with
  // UNSAFE: on the line above is allowed; O.Destroy in a comment or a string is not code. }
unit s03_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TNode = class
  public
    destructor Destroy; override;
  end;

procedure DropTemp;

implementation

destructor TNode.Destroy;
begin
  inherited Destroy;
end;

procedure DropTemp;
var
  O: TNode;
begin
  WriteLn('O.Destroy is not called here');
  O := TNode.Create; // UNSAFE: freed by hand below
  // UNSAFE: O is created on the line above and has no other references
  O.Destroy;
end;

end.
