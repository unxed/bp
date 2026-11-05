// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S24: a class cast that cannot go wrong stays: to the same class, to an ancestor, to TObject; a downcast is `as`;
  a deliberate one is marked. }
unit s24_ok;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Safe;

type
  TShape = class
  public
    Sides: Integer;
  end;

  TSquare = class(TShape)
  public
    Edge: Integer;
  end;

function EdgeOf(const S: TShape): Integer;
function SidesOf(Q: TSquare): Integer;
function Same(S: TShape): TShape;
function Marked(S: TShape): Integer;
function ViaObject(const O: TObject): Integer;

implementation

function EdgeOf(const S: TShape): Integer;
begin
  Result := (S as TSquare).Edge;
end;

function SidesOf(Q: TSquare): Integer;
begin
  // an upcast is free
  Result := TShape(Q).Sides + TObject(Q).InstanceSize;
end;

function Same(S: TShape): TShape;
begin
  Result := TShape(S);
end;

function Marked(S: TShape): Integer;
begin
  // UNSAFE: the caller passes squares only, and this is the hot path
  Result := TSquare(S).Edge;
end;

function ViaObject(const O: TObject): Integer;
begin
  Result := (O as TSquare).Edge;
end;

end.
