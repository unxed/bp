// EXPECT: clean
{ S4: @ of a procedure or a method declared in the module is a procedural value (TDefer.Call, TGroup.Go, a TProcedure
  parameter), not a raw address: @Proc, @Obj.Method, @TFoo.Method, an overloaded and a nested procedure, and spaces
  around the dots are not findings. }
unit s04_proc_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TCounter = class
  public
    Hits: Integer;
    procedure Hit;
  end;

  TCallback = procedure;
  TMethodCallback = procedure of object;

procedure Tick;
procedure Twice; overload;
procedure Twice(const N: Integer); overload;
procedure RunAll(const C: TCounter);

implementation

procedure TCounter.Hit;
begin
  Inc(Hits);
end;

procedure Tick;
begin
end;

procedure Twice;
begin
  Twice(1);
end;

procedure Twice(const N: Integer);
begin
  WriteLn(N * 2);
end;

procedure Call(const P: TCallback; const M: TMethodCallback);
begin
  P();
  M();
end;

procedure RunAll(const C: TCounter);

  procedure Local;
  begin
    Tick;
  end;

begin
  Call(@Tick, @C.Hit);
  Call(@Local, @ C . Hit);
  Call(@Twice, @C.Hit);
end;

end.
