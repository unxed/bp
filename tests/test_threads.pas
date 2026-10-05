{ Нагрузочный тест менеджера потоков (SafeThreads), годится для обоих режимов:
  свои потоки без libc (Linux по умолчанию) и cthreads (-dSAFE_LIBC). Код возврата = число провалов. }
program test_threads;

{$mode objfpc}{$H+}

uses
  SafeThreads, SysUtils, Classes, Safe;

type
  TIntChan = specialize TChan<Integer>;

  { Куча, строки и исключения внутри потока. }
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

var
  Failed: Integer = 0;
  Ev: PEventState; // ручной сброс: на этом построен SyncObjs.TEvent
  Shared: LongInt = 0;
  CS: TRTLCriticalSection;

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
    EnterCriticalSection(CS);   // рекурсивный замок RTL
    EnterCriticalSection(CS);
    Inc(Shared);
    LeaveCriticalSection(CS);
    LeaveCriticalSection(CS);
  end;
  FOut.Send(Length(S) + Caught + Length(L));
end;

procedure TPlainThread.Execute;
begin
  BasicEventWaitFor(Cardinal($FFFFFFFF), Ev); // без таймаута
  Value := 42;
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
  T := TPlainThread.Create(False);
  Sleep(20);
  BasicEventSetEvent(Ev);
  T.WaitFor;
  Check(T.Value = 42, 'TThread + manual-reset BasicEvent');
  // UNSAFE: классический RTL-код, владельца нет
  T.Destroy;
  BasicEventDestroy(Ev);
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
  {$if declared(SafeRawThreadCount)}
  Sleep(50);
  Check(SafeRawThreadCount = 0, 'raw: all threads finished');
  {$endif}
  DoneCriticalSection(CS);
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
