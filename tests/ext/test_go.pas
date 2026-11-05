{ Tests of goroutines and channels (SPEC §14). Exit code = number of failures. }
program test_go;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

type
  TIntChan = specialize TChan<Integer>;
  TInts = array of Integer;
  TArrChan = specialize TChan<TInts>;

  { A task: the data are fields, the code is Run. }
  TSquare = class(TTask)
  private
    FN: Integer;
    FOut: TIntChan;
  public
    constructor Create(const AN: Integer; const AOut: TIntChan);
    procedure Run; override;
  end;

  TBoom = class(TTask)
  public
    procedure Run; override;
  end;

  { Waits for the group to be cancelled with Select on Done. }
  TWaiter = class(TTask)
  private
    FIn, FAck: TIntChan;
  public
    constructor Create(const AIn, AAck: TIntChan);
    procedure Run; override;
  end;

var
  Failed: Integer = 0;
  Counter: LongInt = 0;

constructor TSquare.Create(const AN: Integer; const AOut: TIntChan);
begin
  inherited Create;
  FN := AN;
  FOut := AOut;
end;

procedure TSquare.Run;
begin
  FOut.Send(FN * FN);
end;

procedure TBoom.Run;
begin
  raise EConvertError.Create('boom');
end;

constructor TWaiter.Create(const AIn, AAck: TIntChan);
begin
  inherited Create;
  FIn := AIn;
  FAck := AAck;
end;

procedure TWaiter.Run;
var
  V: Integer;
begin
  repeat
    case Select([FIn.Sel, Done]) of
      // UNSAFE: the only task that writes Counter in this test; the main block reads it after Wait
      0: if FIn.TryRecv(V) then
         begin
           Inc(Counter, V);
           FAck.Send(V);
         end;
      1: Exit; // the group is cancelled
    end;
  until False;
end;

procedure Bump;
begin
  InterlockedIncrement(Counter);
end;

procedure Check(const Cond: Boolean; const What: string);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

procedure FanIn;
var
  G: TGroup;
  Ch: TIntChan;
  I, V, Sum: Integer;
begin
  G := TGroup.Create;
  Ch := TIntChan.Create; // unbuffered: rendezvous
  for I := 1 to 10 do
    G.Go(TSquare.Create(I, Ch));
  Sum := 0;
  for I := 1 to 10 do
    if Ch.Recv(V) then
      Inc(Sum, V);
  G.Wait;
  Check(Sum = 385, 'go: fan-in over unbuffered channel, sum of squares = 385');
end;

procedure Buffered;
var
  Ch: TIntChan;
  V, Sum: Integer;
begin
  Ch := TIntChan.Create(3);
  Ch.Send(1); Ch.Send(2); Ch.Send(3); // does not block: buffer of 3
  Ch.Close;
  Sum := 0;
  for V in Ch do // range ch: until closed and drained
    Inc(Sum, V);
  Check(Sum = 6, 'chan: buffered send without receiver, range until closed');
  Check(not Ch.Recv(V) and (V = 0), 'chan: Recv on closed and drained returns False');
  try
    Ch.Send(4);
    Check(False, 'chan: send on closed raises R6');
  except
    on E: ESafety do Check(Pos('SAFE-R6', E.Message) > 0, 'chan: send on closed raises R6');
  end;
  try
    Ch.Close;
    Check(False, 'chan: double close raises R6');
  except
    on E: ESafety do Check(Pos('SAFE-R6', E.Message) > 0, 'chan: double close raises R6');
  end;
end;

{ R17 (debug checks): a dynamic array sent while a second variable holds it. }
procedure SharedArray;
var
  Ch: TArrChan;
  A, B, Got: TInts;
  Was: Boolean;
begin
  Ch := TArrChan.Create(2);
  Was := SafeDebugChecks;
  SafeDebugChecks := True; // UNSAFE: one goroutine runs the tests
  try
    SetLength(A, 2);
    Ch.Send(A); // UNSAFE: the only holder, then B shares A on purpose for R17
    B := A;
    try
      Ch.Send(A);
      Check(False, 'chan: a shared array raises R17');
    except
      on E: ESafety do Check(Pos('SAFE-R17', E.Message) > 0, 'chan: a shared array raises R17');
    end;
    Ch.Send(Copy(B));
    Check(Ch.Recv(Got) and (Length(Got) = 2), 'chan: R17 lets a moved array and a copy through');
  finally
    SafeDebugChecks := Was; // UNSAFE: one goroutine runs the tests
  end;
end;

procedure Failure;
var
  G: TGroup;
begin
  G := TGroup.Create;
  G.Go(TBoom.Create);
  try
    G.Wait;
    Check(False, 'group: task exception surfaces in Wait (R7)');
  except
    on E: ESafety do
      Check((Pos('SAFE-R7', E.Message) > 0) and (Pos('EConvertError: boom', E.Message) > 0),
        'group: task exception surfaces in Wait (R7) with original class and message');
  end;
  Check(G.Cancelled, 'group: first failure cancels the group');
end;

procedure SelectAndCancel;
var
  G: TGroup;
  A, B, Ack: TIntChan;
  T0: QWord;
  V: Integer;
begin
  A := TIntChan.Create(1);
  B := TIntChan.Create(1);
  T0 := GetTickCount64;
  Check(Select([A.Sel, B.Sel], 50) = -1, 'select: timeout returns -1');
  Check(GetTickCount64 - T0 >= 40, 'select: timeout actually waited');
  B.Send(7);
  Check(Select([A.Sel, B.Sel], 1000) = 1, 'select: ready channel index');

  Counter := 0;
  Ack := TIntChan.Create(2);
  G := TGroup.Create;
  G.Go(TWaiter.Create(A, Ack));
  A.Send(5);
  A.Send(6);
  // both values taken before the cancel: a Select that sees A empty and Done closed may otherwise leave 6 (found by
  // BP_SCHED_SEED=3)
  Ack.Recv(V);
  Ack.Recv(V);
  G.Cancel;
  G.Wait;
  Check(Counter = 11, 'select: worker received values, then stopped on Done');
end;

procedure Structured;
var
  G: TGroup;
  I: Integer;
begin
  Counter := 0;
  G := TGroup.Create;
  for I := 1 to 200 do
    G.Go(@Bump);
end; // leaving the scope waits for all tasks

begin
{$if defined(go32v2) or defined(msdos)}
  WriteLn('skipped: DOS has no threads (TGroup.Go raises SAFE-R8)');
  Halt(0);
{$endif}
  WriteLn('-- FanIn'); FanIn;
  WriteLn('-- Buffered'); Buffered;
  WriteLn('-- SharedArray'); SharedArray;
  WriteLn('-- Failure'); Failure;
  WriteLn('-- SelectAndCancel'); SelectAndCancel;
  WriteLn('-- Structured'); Structured;
  Check(Counter = 200, 'group: scope exit waits for all 200 tasks');
  try
    SafeCheckNoLeaks;
    Check(True, 'leaks: nothing left (R5)');
  except
    on E: ESafety do Check(False, 'leaks: ' + E.Message);
  end;
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
