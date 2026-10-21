// EXPECT: clean
{ S6: TFoo.Create goes at once to an owner (Own, Share, Adopt, raise), or a // UNSAFE: mark says who owns it;
  constructor TFoo.Create and inherited Create are not calls; TArena.Create makes a value, not an object. }
unit s06_ok;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Safe;

type
  TNode = class
  public
    constructor Create;
  end;
  TNodeBox = specialize TOwned<TNode>;
  TNodeRef = specialize TShared<TNode>;

procedure Owners;
procedure Fail;

implementation

constructor TNode.Create;
begin
  inherited Create;
end;

procedure Owners;
var
  A: TNodeBox;
  B: TNodeRef;
  Ar: TArena;
  O: TObject;
begin
  A := TNodeBox.Own(TNode.Create);
  B := TNodeRef.Share(TNode.Create);
  Ar := TArena.Create;
  Ar.Adopt(TNode.Create);
  // UNSAFE: the object is freed by the caller of the test
  O := TNode.Create;
  if O = nil then
    Exit;
  O := TNode.Create; // UNSAFE: the object is freed by the caller of the test
end;

procedure Fail;
begin
  raise Exception.Create('no');
end;

end.
