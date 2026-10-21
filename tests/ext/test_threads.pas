{ A load test of the thread manager (BPThreads) for both modes:
  threads without libc (the Linux default) and cthreads (-dSAFE_LIBC). Exit code = number of failures. }
program test_threads;

{$mode objfpc}{$H+}

// UNSAFE: BP goes first for the thread manager (SPEC §14); SysUtils and Classes after it shadow it, and the
// program does not free objects by hand (no FreeAndNil)
uses
  BP, SysUtils, Classes;

type
  TIntChan = specialize TChan<Integer>;

  { The heap, strings and exceptions inside a thread. }
  TChurn = class(TTask)
  private
    FN: Integer;
    FOut: TIntChan;
  public
    constructor Create(AN: Integer; const AOut: TIntChan);
    procedure Run; override;
  end;

  TPlainThread = class(TThread)
  public
    Value: Integer;
    procedure Execute; override;
  end;

  { The object behind a TWeak in the stress test: its destructor counts itself and spoils the magic. }
  TStressObj = class
  public
    Magic: LongInt;
    constructor Create;
    destructor Destroy; override;
  end;
  TStressShared = specialize TShared<TStressObj>;
  TStressWeak = specialize TWeak<TStressObj>;

  { Locks GWeak again and again while the main thread drops the last strong reference (H6). }
  TWeakHammer = class(TTask)
  public
    procedure Run; override;
  end;

var
  Failed: Integer = 0;
  Ev: PEventState; // manual reset: SyncObjs.TEvent is built on this
  Shared: LongInt = 0;
  CS: TRTLCriticalSection;
  GWeak: TStressWeak;            // written by the main thread only while no hammer runs
  GDestroyed: LongInt = 0;       // destructors of TStressObj
  GBad: LongInt = 0;             // a locked object that was already destroyed
  GLocked: LongInt = 0;          // successful TryLock calls
  GSpin: LongInt = 0;

const
  StressMagic = $5AFE;

constructor TChurn.Create(AN: Integer; const AOut: TIntChan);
begin
  inherited Create;
  FN := AN;
  FOut := AOut;
end;

procedure TChurn.Run;
var
  S: string;
  I, Caught: Integer;
  L: specialize TArray<string>;
begin
  S := '';
  Caught := 0;
  SetLength(L, 0);
  for I := 1 to 200 do
  begin
    S := S + IntToStr(I mod 10);
    SetLength(L, Length(L) + 1);
    L[High(L)] := 'ё' + S;
    try
      if I mod 50 = 0 then
        raise EConvertError.Create('x' + IntToStr(I));
    except
      on E: EConvertError do Inc(Caught);
    end;
    EnterCriticalSection(CS);   // the recursive RTL lock
    EnterCriticalSection(CS);
    Inc(Shared);
    LeaveCriticalSection(CS);
    LeaveCriticalSection(CS);
  end;
  FOut.Send(Length(S) + Caught + Length(L));
end;

procedure TPlainThread.Execute;
begin
  BasicEventWaitFor(Cardinal($FFFFFFFF), Ev); // no timeout
  Value := 42;
end;

constructor TStressObj.Create;
begin
  inherited Create;
  Magic := StressMagic;
end;

destructor TStressObj.Destroy;
begin
  Magic := 0;
  InterlockedIncrement(GDestroyed);
  inherited Destroy;
end;

procedure TWeakHammer.Run;
var
  L: TStressShared;
  N: Integer;
begin
  N := 0;
  // once TryLock fails the object is gone for good; the cap only guards against a hang
  while (N < 1000000) and L.TryLock(GWeak) do
  begin
    if L.Get.Magic <> StressMagic then
      InterlockedIncrement(GBad);
    InterlockedIncrement(GLocked);
    L.Reset;
    Inc(N);
  end;
end;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

procedure Churn(Rounds, PerRound: Integer);
var
  G: TGroup;
  Ch: TIntChan;
  R, I, V, Sum: Integer;
begin
  Shared := 0;
  Sum := 0;
  for R := 1 to Rounds do
  begin
    G := TGroup.Create;
    Ch := TIntChan.Create(PerRound);
    for I := 1 to PerRound do
      G.Go(TChurn.Create(I, Ch));
    G.Wait;
    for I := 1 to PerRound do
      if Ch.Recv(V) then
        Inc(Sum, V);
  end;
  Check(Sum = Rounds * PerRound * (200 + 4 + 200), Format('churn: %d tasks with heap, strings, exceptions', [Rounds * PerRound]));
  Check(Shared = Rounds * PerRound * 200, 'churn: recursive critical section, no lost increments');
end;

procedure PlainTThread;
var
  T: TPlainThread;
begin
  Ev := BasicEventCreate(nil, True, False, '');
  T := TPlainThread.Create(False); // UNSAFE: a TThread, the runtime of FPC owns it
  Sleep(20);
  BasicEventSetEvent(Ev);
  T.WaitFor;
  Check(T.Value = 42, 'TThread + manual-reset BasicEvent');
  // UNSAFE: classic RTL code, no owner
  T.Destroy;
  BasicEventDestroy(Ev);
end;

{ TWeak.TryLock in several threads against the last Reset in the main thread (H6): every object is destroyed exactly
  once, and no TryLock gives an object that is already destroyed or revives it. }
procedure WeakStress(Rounds, Hammers: Integer);
var
  G: TGroup;
  S: TStressShared;
  R, I, J: Integer;
  Before: LongInt;
  T0: QWord;
begin
  GDestroyed := 0;
  GBad := 0;
  GLocked := 0;
  for R := 1 to Rounds do
  begin
    S := TStressShared.Share(TStressObj.Create);
    GWeak := S.Weak;
    Before := GLocked;
    G := TGroup.Create;
    for I := 1 to Hammers do
      G.Go(TWeakHammer.Create);
    T0 := GetTickCount64;
    while (GLocked = Before) and (GetTickCount64 - T0 < 1000) do // a hammer is running: the race is real
      ThreadSwitch;
    for J := 1 to (R * 7919) mod 20000 do // a different moment of the last Reset in every round
      InterlockedIncrement(GSpin);
    S.Reset; // the last strong reference of the main thread; a hammer may hold the object a little longer
    G.Wait;
    GWeak.Reset;
  end;
  Check(GDestroyed = Rounds, Format('weak stress: %d objects destroyed exactly once (destroyed %d)', [Rounds, GDestroyed]));
  Check(GBad = 0, Format('weak stress: no destroyed object locked (%d bad of %d locks)', [GBad, GLocked]));
  Check(GLocked > 0, 'weak stress: the hammers did lock the objects');
end;

procedure Timeout;
var
  E: PRTLEvent;
  T0: QWord;
begin
  E := RTLEventCreate;
  T0 := GetTickCount64;
  RTLEventWaitFor(E, 100);
  Check(GetTickCount64 - T0 >= 90, 'RTLEvent timeout waits');
  RTLEventSetEvent(E);
  T0 := GetTickCount64;
  RTLEventWaitFor(E, 5000);
  Check(GetTickCount64 - T0 < 1000, 'RTLEvent set before wait is not lost');
  RTLEventDestroy(E);
end;

begin
{$if defined(go32v2) or defined(msdos)}
  WriteLn('skipped: DOS has no threads');
  Halt(0);
{$endif}
  InitCriticalSection(CS);
  WriteLn('-- Churn'); Churn(10, 50);
  WriteLn('-- TThread'); PlainTThread;
  WriteLn('-- Timeout'); Timeout;
  WriteLn('-- Many'); Churn(40, 25);
  WriteLn('-- WeakStress'); WeakStress(300, 4);
  {$if declared(SafeRawThreadCount)}
  Sleep(50);
  Check(SafeRawThreadCount = 0, 'raw: all threads finished');
  {$endif}
  DoneCriticalSection(CS);
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
