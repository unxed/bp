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

  { Sends 1..FN over FOut with Select, or stops on Done. }
  TSelSender = class(TTask)
  private
    FOut: TIntChan;
    FN: Integer;
  public
    constructor Create(const AOut: TIntChan; const AN: Integer);
    procedure Run; override;
  end;

  { Receives FN values with Select and sends their sum. }
  TSelReceiver = class(TTask)
  private
    FIn, FSum: TIntChan;
    FN: Integer;
  public
    constructor Create(const AIn, ASum: TIntChan; const AN: Integer);
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

constructor TSelSender.Create(const AOut: TIntChan; const AN: Integer);
begin
  inherited Create;
  FOut := AOut;
  FN := AN;
end;

procedure TSelSender.Run;
var
  I: Integer;
begin
  for I := 1 to FN do
    if Select([FOut.SendCase(I), Done.RecvCase]) = 1 then
      Exit;
end;

constructor TSelReceiver.Create(const AIn, ASum: TIntChan; const AN: Integer);
begin
  inherited Create;
  FIn := AIn;
  FSum := ASum;
  FN := AN;
end;

procedure TSelReceiver.Run;
var
  I, V, Sum: Integer;
begin
  Sum := 0;
  for I := 1 to FN do
    if Select([FIn.RecvCase(V)]) = 0 then
      Inc(Sum, V);
  FSum.Send(Sum);
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

procedure AtomicSelect;
const
  N = 2000;
var
  G: TGroup;
  A, B, U, Sum: TIntChan;
  V, W, I, Got, Picks0, Picks1: Integer;
  Ok, Raised: Boolean;
begin
  // a send case into a buffer with room, then a receive case takes the value
  A := TIntChan.Create(1);
  B := TIntChan.Create(1);
  Check(Select([A.SendCase(5), B.RecvCase(V)], 0) = 0, 'atomic select: a send case into a free buffer');
  V := 0;
  Check((Select([B.RecvCase(W), A.RecvCase(V)], 0) = 1) and (V = 5), 'atomic select: the receive case gets the value');
  Check(Select([A.RecvCase(V), B.RecvCase(V)], 30) = -1, 'atomic select: timeout returns -1');
  Check(Select([A.RecvCase(V)], 0) = -1, 'atomic select: TimeoutMs 0 does not wait');

  // two ready cases: exactly one happens, and both are picked over many rounds
  Picks0 := 0;
  Picks1 := 0;
  for I := 1 to 200 do
  begin
    A.Send(1);
    B.Send(2);
    case Select([A.RecvCase(V), B.RecvCase(W)]) of
      0: if (V = 1) and B.TryRecv(W) and not A.TryRecv(V) then Inc(Picks0);
      1: if (W = 2) and A.TryRecv(V) and not B.TryRecv(W) then Inc(Picks1);
    end;
  end;
  Check((Picks0 > 0) and (Picks1 > 0) and (Picks0 + Picks1 = 200),
    Format('atomic select: exactly one of two ready cases, picked at random (%d and %d of 200)', [Picks0, Picks1]));

  // unbuffered: a send case and a receive case in two goroutines meet; every value arrives exactly once
  U := TIntChan.Create;
  Sum := TIntChan.Create(1);
  G := TGroup.Create;
  G.Go(TSelSender.Create(U, N));
  G.Go(TSelReceiver.Create(U, Sum, N));
  Sum.Recv(Got);
  G.Wait;
  Check(Got = N * (N + 1) div 2, Format('atomic select: unbuffered send and receive cases, sum %d', [Got]));

  // a sender blocked in a send case stops on Done
  G := TGroup.Create;
  G.Go(TSelSender.Create(U, 1));
  Sleep(20);
  G.Cancel;
  G.Wait;
  Check(not U.TryRecv(V), 'atomic select: a cancelled send case sent nothing');

  // closed: a receive case gets Ok = False, a send case raises R6
  A.Close;
  Ok := True;
  Check((Select([A.RecvCase(V, Ok)], 0) = 0) and not Ok and (V = 0), 'atomic select: a closed channel gives Ok = False');
  Raised := False;
  try
    Select([A.SendCase(1)]);
  except
    on ESafety do Raised := True;
  end;
  Check(Raised, 'atomic select: a send case into a closed channel raises R6');
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
  WriteLn('-- AtomicSelect'); AtomicSelect;
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
