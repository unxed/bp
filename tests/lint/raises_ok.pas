// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S30: every interface routine that may raise carries the mark with what it raises: the raise statements of its body,
  the routines of the module it calls, the marks of raises_lib, the table of the RTL (StrToInt), minus what its
  handlers take; a re-raise raises again what its handler took. A private method needs no mark; a call through a
  procedure variable counts nothing. }
unit raises_ok;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, raises_lib, Safe;

type
  EConfig = class(Exception);
  EMissing = class(EConfig);

  TConfig = class
  private
    FCount: Integer;
    procedure Fail(const Key: String);
  public
    function Get(const Key: String): String;  // raises: EMissing
  end;

function ReadPort(const S: String): Integer;  // raises: EConvertError, EParse
// raises: EParse
function PortOr(const S: String; const Default: Integer): Integer;
function Quiet(const S: String): Integer;
procedure Require(const Key: String);  // raises: EMissing
procedure Again(const Key: String);  // raises: EMissing
function Even(const N: Integer): Boolean;  // raises: EConfig
function Odd_(const N: Integer): Boolean;  // raises: EConfig
procedure Pass(const Key: String);
procedure Indirect(const P: TProcedure);

implementation

procedure TConfig.Fail(const Key: String);
begin
  raise EMissing.Create(Key);
end;

function TConfig.Get(const Key: String): String;
begin
  Inc(FCount);
  if Key = '' then
    Fail(Key);
  Result := Key;
end;

function ReadPort(const S: String): Integer;
begin
  Result := StrToInt(S) + LibParse(S);
end;

function PortOr(const S: String; const Default: Integer): Integer;
begin
  try
    Result := ReadPort(S);
  except
    on E: EConvertError do
      Result := Default;
  end;
end;

function Quiet(const S: String): Integer;
begin
  try
    Result := ReadPort(S);
  except
    Result := 0;
  end;
end;

procedure Require(const Key: String);
begin
  try
    if Key = '' then
      raise EMissing.Create('key');
    LibCheck(Key <> '-');
  except
    on E: ELibError do
      WriteLn(E.Message);
    on E: EConfig do
      raise;
  end;
end;

procedure Again(const Key: String);
begin
  try
    Require(Key);
  except
    on E: Exception do
      raise E;
  end;
end;

function Even(const N: Integer): Boolean;
begin
  if N < 0 then
    raise EConfig.Create('negative');
  Result := (N = 0) or Odd_(N - 1);
end;

function Odd_(const N: Integer): Boolean;
begin
  Result := (N <> 0) and Even(N - 1);
end;

procedure Hidden(const Key: String);
begin
  raise EMissing.Create(Key);
end;

procedure Pass(const Key: String);
var
  P: TProcedure;
begin
  try
    Hidden(Key);
  except
    on E: EConfig do
      WriteLn(E.Message);
  end;
  P := nil;
  Indirect(P);
end;

procedure Indirect(const P: TProcedure);
begin
  if Assigned(P) then
    P();
end;

end.
