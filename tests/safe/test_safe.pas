{ Рантайм-тесты Safe Pascal. Собирается без опций: run.sh кладёт рядом safe.pas
  и вызывает просто `fpc test_safe.pas` (проверка обещания SPEC §2).
  Код возврата = число проваленных проверок. }
program test_safe;

{$mode objfpc}{$H+}

uses
  SysUtils, Safe;

type
  TProbe = class
  public
    Name: string;
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;

  TIntf = class(TInterfacedObject);

  TProbeBox = specialize TOwned<TProbe>;
  TProbeRef = specialize TShared<TProbe>;
  TProbeWeak = specialize TWeak<TProbe>;
  TInts = specialize TArray<Integer>;
  TIntSlice = specialize TSlice<Integer>;

var
  Log: string = ''; // '~имя' на каждое уничтожение, по порядку
  Failed: Integer = 0;

constructor TProbe.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
end;

destructor TProbe.Destroy;
begin
  Log := Log + '~' + Name;
  inherited Destroy;
end;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What, '   [log=', Log, ']');
    Inc(Failed);
  end;
end;

procedure OwnedScope;
var
  A: TProbeBox;
begin
  A := TProbeBox.Own(TProbe.Create('a'));
  Check(Log = '', 'owned: alive inside scope');
  Check(A.Get.Name = 'a', 'owned: Get');
end;

procedure OwnedMove;
var
  A, B: TProbeBox;
  P: TProbe;
begin
  A := TProbeBox.Own(TProbe.Create('b'));
  B := A.Move;
  Check(A.IsEmpty and not B.IsEmpty, 'owned: Move empties source');
  Check(not A.TryGet(P) and (P = nil), 'owned: TryGet on empty');
  try
    A.Get;
    Check(False, 'owned: Get on moved-from raises');
  except
    on E: ESafety do Check(Pos('SAFE-R1', E.Message) > 0, 'owned: Get on moved-from raises R1');
  end;
  B.Reset;
  Check(Log = '~b', 'owned: Reset destroys');
  A := TProbeBox.Own(TProbe.Create('b2'));
  A := A.Move; // самоперенос не должен уничтожить объект
  Check((Log = '~b') and (A.Get.Name = 'b2'), 'owned: A := A.Move keeps object');
end;

procedure OwnedAccidentalCopy;
var
  A, C: TProbeBox;
begin
  A := TProbeBox.Own(TProbe.Create('c'));
  C := A; // нарушение контракта (линтер), но память должна остаться целой
  A.Reset;
  Check(Log = '', 'owned: copy keeps object alive');
  C.Reset;
  Check(Log = '~c', 'owned: destroyed exactly once');
end;

procedure RaiseInside;
var
  A: TProbeBox;
begin
  A := TProbeBox.Own(TProbe.Create('d'));
  raise Exception.Create('boom');
end;

procedure OwnedException;
begin
  try
    RaiseInside;
  except
    on E: Exception do ;
  end;
  Check(Log = '~d', 'owned: destroyed on exception (RAII)');
end;

procedure SharedAndWeak;
var
  A, B, L: TProbeRef;
  W: TProbeWeak;
begin
  A := TProbeRef.Share(TProbe.Create('e'));
  B := A;
  A.Reset;
  Check(Log = '', 'shared: alive while one ref remains');
  W := B.Weak;
  Check(W.IsAlive, 'weak: alive');
  Check(L.TryLock(W) and (L.Get.Name = 'e'), 'weak: TryLock succeeds');
  B.Reset;
  Check(Log = '', 'weak: locked ref keeps object');
  L.Reset;
  Check(Log = '~e', 'shared: destroyed with last strong ref');
  Check(not W.IsAlive, 'weak: dead after destroy');
  Check(not L.TryLock(W) and L.IsEmpty, 'weak: TryLock fails safely');
end;

procedure InterfacedRejected;
var
  A: specialize TOwned<TIntf>;
begin
  try
    A := specialize TOwned<TIntf>.Own(TIntf.Create);
    Check(False, 'R3: Own(TInterfacedObject) raises');
  except
    on E: ESafety do Check(Pos('SAFE-R3', E.Message) > 0, 'R3: Own(TInterfacedObject) raises');
  end;
end;

procedure Slices;
var
  A: TInts;
  S, T: TIntSlice;
  I: Integer;
begin
  SetLength(A, 5);
  for I := 0 to 4 do
    A[I] := I + 1;
  S := TIntSlice.From(A);
  T := S.Sub(1, 3);
  Check((T.Len = 3) and (T[0] = 2) and (T[2] = 4), 'slice: Sub and index');
  T[0] := 20;
  Check(A[1] = 20, 'slice: writes visible in source (Go semantics)');
  Check(Length(T.ToArray) = 3, 'slice: ToArray');
  try
    I := T[3];
    Check(False, 'slice: index out of bounds raises');
  except
    on E: ESafety do Check(Pos('SAFE-R2', E.Message) > 0, 'slice: index out of bounds raises R2');
  end;
  try
    T := S.Sub(4, 2);
    Check(False, 'slice: Sub out of bounds raises');
  except
    on E: ESafety do Check(Pos('SAFE-R2', E.Message) > 0, 'slice: Sub out of bounds raises R2');
  end;
  A := nil;
  Check(S[4] = 5, 'slice: keeps array alive after source dropped');
end;

procedure ArenaScope;
var
  Ar, Bad: TArena;
  P: TProbe;
begin
  Ar := TArena.Create;
  Ar.Adopt(TProbe.Create('x'));
  Ar.Adopt(TProbe.Create('y'));
  P := Ar.Adopt(TProbe.Create('z')) as TProbe;
  Check((P.Name = 'z') and (Ar.Count = 3), 'arena: Adopt');
  Ar.FreeAll;
  Check(Log = '~z~y~x', 'arena: FreeAll in reverse order');
  Ar.Adopt(TProbe.Create('w'));
  try
    Bad.Count;
    Check(False, 'arena: not created raises');
  except
    on E: ESafety do Check(Pos('SAFE-R4', E.Message) > 0, 'arena: not created raises R4');
  end;
end;

type
  TDeferProbe = class
  public
    Hits: Integer;
    procedure Hit;
    procedure Boom;
  end;

procedure TDeferProbe.Hit;
begin
  Inc(Hits);
end;

procedure TDeferProbe.Boom;
begin
  raise Exception.Create('boom in a deferred call');
end;

var
  Probe: TDeferProbe;

procedure DeferScope;
var
  D: TDefer;
begin
  D := TDefer.Call(@Probe.Hit);
  Check(Probe.Hits = 0, 'defer: not called yet inside the scope');
end;

procedure DeferCancelled;
var
  D: TDefer;
begin
  D := TDefer.Call(@Probe.Hit);
  D.Cancel;
end;

procedure DeferWithException;
var
  D: TDefer;
begin
  D := TDefer.Call(@Probe.Hit);
  raise Exception.Create('x');
end;

procedure Defers;
begin
  Probe := TDeferProbe.Create;
  DeferScope;
  Check(Probe.Hits = 1, 'defer: called at scope exit');
  DeferCancelled;
  Check(Probe.Hits = 1, 'defer: Cancel skips the call');
  try
    DeferWithException;
  except
    on E: Exception do ;
  end;
  Check(Probe.Hits = 2, 'defer: called when the scope is left by an exception');
  // UNSAFE: Probe is a plain object of this test, nothing else owns it
  Probe.Destroy;
end;

procedure Leaks;
var
  A: TProbeBox;
begin
  Check(SafeLiveCount = 0, 'leaks: nothing alive after the scenarios above');
  SafeCheckNoLeaks; // must not raise
  A := TProbeBox.Own(TProbe.Create('leak'));
  Check(SafeLiveCount = 1, 'leaks: an owned object is counted');
  try
    SafeCheckNoLeaks;
    Check(False, 'leaks: SafeCheckNoLeaks raises with a live object');
  except
    on E: ESafety do Check(Pos('SAFE-R5', E.Message) > 0, 'leaks: SafeCheckNoLeaks raises R5 with a live object');
  end;
  A.Reset;
  Check(SafeLiveCount = 0, 'leaks: Reset releases the count');
end;

procedure DeferFailureIsCounted;
var
  D: TDefer;
  P: TDeferProbe;
begin
  P := TDeferProbe.Create;
  D := TDefer.Call(@P.Boom);
  D := Default(TDefer); // the deferred call runs now and raises inside the destructor of the guard
  Check(SafeDeferFailures = 1, 'defer: an exception inside a deferred call is counted, not lost');
  try
    SafeCheckNoLeaks;
    Check(False, 'defer: SafeCheckNoLeaks reports the suppressed exception');
  except
    on E: ESafety do Check(Pos('SAFE-R5', E.Message) > 0, 'defer: SafeCheckNoLeaks reports the suppressed exception (R5)');
  end;
  // UNSAFE: P is a plain object of this test, nothing else owns it
  P.Destroy;
end;

procedure Run(const Name: string; Proc: TProcedure; const ExpectLog: string);
begin
  Log := '';
  WriteLn('-- ', Name);
  Proc;
  if ExpectLog <> '' then
    Check(Log = ExpectLog, Name + ': log after scope = ' + ExpectLog);
end;

begin
  Run('OwnedScope', @OwnedScope, '~a');
  Run('OwnedMove', @OwnedMove, '~b~b2');
  Run('OwnedAccidentalCopy', @OwnedAccidentalCopy, '~c');
  Run('OwnedException', @OwnedException, '~d');
  Run('SharedAndWeak', @SharedAndWeak, '~e');
  Run('InterfacedRejected', @InterfacedRejected, '');
  Run('Slices', @Slices, '');
  Run('ArenaScope', @ArenaScope, '~z~y~x~w');

  Run('Defers', @Defers, '');
  Run('Leaks', @Leaks, '~leak');
  Run('DeferFailureIsCounted', @DeferFailureIsCounted, '');

  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
