// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S26a: class references assigned on every path before they are read, and the result and an out parameter before the
  routine returns. }
unit s26a_ok;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Safe;

type
  TFoo = class
  public
    X: Integer;
  end;

function NewFoo: TFoo;
function Make(const C: Boolean): TFoo;
function Pick(const C: Boolean): TFoo;
procedure Find(const C: Boolean; out F: TFoo);
function Kind(const N: Integer): TFoo;
function Guarded: Integer;
function Looped(const N: Integer): Integer;
procedure Fill(var F: TFoo);
function ByVar: Integer;
function Nested: Integer;
function Raised(const C: Boolean): TFoo;  // raises: Exception

implementation

function NewFoo: TFoo;
begin
  // UNSAFE: the caller owns it
  Result := TFoo.Create;
end;

function Make(const C: Boolean): TFoo;
begin
  if C then
    Result := NewFoo
  else
    Result := nil;
end;

function Pick(const C: Boolean): TFoo;
begin
  if C then
    Exit(NewFoo);
  Result := nil;
end;

procedure Find(const C: Boolean; out F: TFoo);
begin
  F := nil;
  if C then
    F := NewFoo;
end;

function Kind(const N: Integer): TFoo;
begin
  case N of
    0: Result := NewFoo;
  else
    Result := nil;
  end;
end;

function Guarded: Integer;
var
  F: TFoo;
begin
  F := nil;
  try
    F := NewFoo;
    Result := F.X;
  finally
    // UNSAFE: the test frees by hand
    F.Destroy;
  end;
end;

function Looped(const N: Integer): Integer;
var
  F: TFoo;
  I: Integer;
begin
  Result := 0;
  repeat
    F := Make(True);
    I := F.X;
  until I >= 0;
  for I := 3 downto 1 do
    F := Make(True);
  Inc(Result, F.X);
  for I := 1 to N do
  begin
    F := Make(False);
    if F <> nil then
      Inc(Result, F.X);
  end;
end;

procedure Fill(var F: TFoo);
begin
  F := nil;
end;

function ByVar: Integer;
var
  F: TFoo;
begin
  Fill(F);
  Result := Ord(F = nil);
end;

function Nested: Integer;
var
  F: TFoo;

  procedure Set1;
  begin
    F := nil;
  end;

begin
  Set1;
  Result := Ord(F = nil);
end;

function Raised(const C: Boolean): TFoo;
begin
  if C then
    raise Exception.Create('no')
  else
    Result := nil;
end;

end.
