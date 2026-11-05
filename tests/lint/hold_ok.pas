// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Hold and Defer of a scope and of a region (safe/SPEC.md section 21.1): a local takes a new object of its class or of a
  descendant, is used and borrowed inside the scope, and is assigned again before a use after it. Hold assigns its
  first argument, so a use right after it is not a read of garbage (S26a). }
unit hold_ok;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Safe;

type
  TFoo = class
  public
    X: Integer;
    procedure Done;
  end;

  TBar = class(TFoo)
  end;

procedure Use(const F: TFoo);
function Scoped(const Name: String): Integer;
function InRegion: Integer;
function Twice: Integer;

implementation

procedure TFoo.Done;
begin
  X := 0;
end;

procedure Use(const F: TFoo);
begin
  F.X := F.X + 1;
end;

function Scoped(const Name: String): Integer;
var
  S: TScopeRef;
  Lines: TStringList;
  F, G: TFoo;
begin
  Result := 0;
  for S in Scope do
  begin
    S.Hold(Lines, TStringList.Create);
    Lines.Add(Name);
    S.Hold(F, TBar.Create);
    S.Defer(@F.Done);
    F.X := Lines.Count;
    G := F;
    Use(G);
    Result := F.X + S.Depth;
  end;
  F := nil;
  G := F;
  Use(G);
end;

function InRegion: Integer;
var
  R: TRegion;
  F: TFoo;
  I: Integer;
begin
  Result := 0;
  R := TRegion.Create;
  for I := 1 to 3 do
  begin
    R.Hold(F, TFoo.Create);
    F.X := I;
    Inc(Result, F.X);
    R.Reset;
  end;
  R.Hold(F,
    TFoo.Create);
  F.X := 1;
end;

function Twice: Integer;
var
  S: TScopeRef;
  F: TFoo;
begin
  Result := 0;
  for S in Scope do
    S.Hold(F, TFoo.Create);
  for S in Scope do
  begin
    S.Hold(F, TFoo.Create);
    Result := F.X;
  end;
end;

end.
