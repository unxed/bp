// EXPECT: clean
{ S10: a TOwned owner moves with .Move and goes to a routine as const (borrow) or var (the callee may take it);
  a TShared reference copies freely; a known copy is marked // UNSAFE:. }
unit s10_ok;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TListBox = specialize TOwned<TStringList>;
  TListRef = specialize TShared<TStringList>;

function Count(const Box: TListBox): Integer;
procedure Take(var Box: TListBox; out Into: TListBox);
procedure Moves;

implementation

function Count(const Box: TListBox): Integer;
begin
  Result := Box.Get.Count;
end;

procedure Take(var Box: TListBox; out Into: TListBox);
begin
  Into := Box.Move;
end;

procedure Moves;
var
  A, B, C: TListBox;
  R, S: TListRef;
begin
  A := TListBox.Own(TStringList.Create);
  B := A.Move;
  Take(B, C);
  // UNSAFE: a second owner on purpose, the counter keeps the object alive
  A := C;
  R := TListRef.Share(TStringList.Create);
  S := R;
  S.Reset;
end;

procedure Shadow;
var
  A, B: TListRef;
begin
  A := TListRef.Share(TStringList.Create);
  B := A;
end;

end.
