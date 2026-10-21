// EXPECT: clean
{ S14: writes through assignment targets, calls, address-taking, loops, with, and nested routines count; exceptions are skipped. }
unit s14_var_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TPoint = record
    X: Integer;
  end;
  // UNSAFE: fixture for S14 pointer-parameter write analysis
  PInt = ^Integer;
  TBase = class
    procedure Update(var N: Integer); virtual; abstract;
  end;
  TChild = class(TBase)
    procedure Update(var N: Integer); override;
  end;

procedure AssignValue(var N: Integer);
procedure AssignField(var P: TPoint);
procedure AssignIndex(var A: array of Integer);
procedure AssignDeref(var P: PInt);
procedure ThroughCall(var N: Integer);
procedure ThroughAddress(var N: Integer);
procedure ThroughFor(var N: Integer);
procedure ThroughWith(var P: TPoint);
procedure ThroughNested(var N: Integer);
procedure ThroughUnsafe(var N: Integer);
procedure Raw(var Buffer);
// UNSAFE: fixture for S14 external-call write analysis
procedure ExternalInput(var N: Integer);

implementation

procedure AssignValue(var N: Integer);
begin
  N := 1;
end;

procedure AssignField(var P: TPoint);
begin
  P.X := 1;
end;

procedure AssignIndex(var A: array of Integer);
begin
  A[0] := 1;
end;

procedure AssignDeref(var P: PInt);
begin
  // UNSAFE: the test deliberately exercises a pointer target.
  P^ := 1;
end;

procedure SetValue(var N: Integer);
begin
  N := 1;
end;

procedure ThroughCall(var N: Integer);
begin
  SetValue(N);
end;

procedure ThroughAddress(var N: Integer);
begin
  // UNSAFE: address-taking is deliberately treated as a write by S14.
  @N;
end;

procedure ThroughFor(var N: Integer);
begin
  for N := 1 to 2 do
    ;
end;

procedure ThroughWith(var P: TPoint);
begin
  with P do
    X := 1;
end;

procedure ThroughNested(var N: Integer);
  procedure Inner;
  begin
    N := 1;
  end;
begin
  Inner;
end;

procedure TChild.Update(var N: Integer);
begin
  WriteLn(N);
end;

// UNSAFE: deliberate input-only var parameter, retained for compatibility.
procedure ThroughUnsafe(var N: Integer);
begin
  WriteLn(N);
end;

procedure Raw(var Buffer);
begin
end;

// UNSAFE: external declaration has no body to analyze.
procedure ExternalInput(var N: Integer); external name 'ExternalInput';

end.
