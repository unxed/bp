{ Runtime tests of Safe Pascal. Built without options: run.sh puts safe.pas next to it
  and simply calls `fpc test_safe.pas` (checking the promise of SPEC §2).
  Exit code = number of failed checks. }
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
  TProbeArenaRef = specialize TArenaRef<TProbe>;

  TCycleNode = class;
  TCycleRef = specialize TShared<TCycleNode>;
  TCycleNode = class(TProbe)
  public
    // UNSAFE: the test makes this cycle on purpose: SafeCheckNoLeaks must report it (H2)
    Next: TCycleRef;
  end;

var
  Log: string = ''; // '~name' for each destruction, in order
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
  A := A.Move; // self-move must not destroy the object
  Check((Log = '~b') and (A.Get.Name = 'b2'), 'owned: A := A.Move keeps object');
end;

procedure OwnedAccidentalCopy;
var
  A, C: TProbeBox;
begin
  A := TProbeBox.Own(TProbe.Create('c'));
  C := A; // UNSAFE: contract violation (S10), but memory must remain intact
  A.Reset;
  Check(Log = '', 'owned: copy keeps object alive');
  C.Reset;
  Check(Log = '~c', 'owned: destroyed exactly once');
end;

procedure OwnedCopyCaughtInDebug;
var
  A, C, D: TProbeBox;
  Caught: string;
begin
  SafeDebugChecks := True;
  try
    D := TProbeBox.Own(TProbe.Create('k1'));
    D.Reset; // the only owner: no finding
    A := TProbeBox.Own(TProbe.Create('k'));
    C := A; // UNSAFE: the copy that the debug check (R9) must catch
    Caught := '';
    try
      A.Reset;
    except
      on E: ESafety do
        Caught := E.Message;
    end;
    Check((Pos('SAFE-R9', Caught) > 0) and (Pos('TProbe', Caught) > 0), 'owned: SAFE_DEBUG catches a copy (R9)');
  finally
    SafeDebugChecks := False;
  end;
  A.Reset;
  C.Reset;
  Check(Log = '~k1~k', 'owned: destroyed exactly once after R9');
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

procedure ArenaRefAfterFreeAll;
var
  Ar: TArena;
  R, Plain: TProbeArenaRef;
  Caught: string;
begin
  Ar := TArena.Create;
  Check(Ar.Generation = 0, 'arena: generation 0 after Create');
  Plain := TProbeArenaRef.Adopt(TProbe.Create('g1'), Ar); // checks off: a plain reference
  SafeDebugChecks := True;
  try
    R := TProbeArenaRef.Adopt(TProbe.Create('g2'), Ar);
    Check((R.Get.Name = 'g2') and not R.IsStale, 'arena ref: Get before FreeAll');
    Ar.FreeAll;
    Check((Ar.Generation = 1) and R.IsStale, 'arena ref: FreeAll bumps the generation');
    Check(not Plain.IsStale, 'arena ref: without debug checks no arena link is kept');
    Caught := '';
    try
      R.Get;
    except
      on E: ESafety do
        Caught := E.Message;
    end;
    Check((Pos('SAFE-R10', Caught) > 0) and (Pos('TProbe', Caught) > 0),
      'arena ref: SAFE_DEBUG catches use after FreeAll (R10)');
    R := TProbeArenaRef.Adopt(TProbe.Create('g3'), Ar);
    Check((R.Get.Name = 'g3') and not R.IsStale, 'arena ref: a new reference after FreeAll is valid');
  finally
    SafeDebugChecks := False;
  end;
  R := TProbeArenaRef.Adopt(TProbe.Create('g4'), Ar); // reuses R: the debug link must be cleared
  Check(not R.IsStale and (R.Get.Name = 'g4'), 'arena ref: re-Adopt without checks clears the link');
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
  Probe: TDeferProbe; // borrow: nobody frees it, the probe of the defer tests lives to the end of the program

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
  Probe := TDeferProbe.Create; // UNSAFE: the probe of the defer tests lives to the end of the program
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

procedure SharedCycleReported;
var
  A, B, C, Tmp: TCycleRef;
  PA: TCycleNode;
  Caught: string;
begin
  SafeDebugChecks := True;
  try
    A := TCycleRef.Share(TCycleNode.Create('h1'));
    B := TCycleRef.Share(TCycleNode.Create('h2'));
    C := TCycleRef.Share(TCycleNode.Create('h3')); // held from outside: not a part of the report
    A.Get.Next := B;
    B.Get.Next := A;
    PA := A.Get;
    A.Reset; // UNSAFE: the cycle keeps the object alive, PA breaks it below
    B.Reset;
    Check(SafeLiveCount = 3, 'cycle: the two objects of the cycle leak');
    Caught := '';
    try
      SafeCheckNoLeaks;
    except
      on E: ESafety do
        Caught := E.Message;
    end;
    WriteLn('     ', Caught);
    Check((Pos('SAFE-R5: 3 owned object(s) still alive', Caught) > 0)
      and (Pos('2 of them are reachable only from each other', Caught) > 0)
      and (Pos('types TCycleNode,', Caught) > 0)
      and (Pos('path TCycleNode -> TCycleNode -> TCycleNode;', Caught) > 0)
      and (Pos('TWeak', Caught) > 0), 'cycle: SafeCheckNoLeaks reports the TShared cycle (H2)');
  finally
    SafeDebugChecks := False;
  end;
  Tmp := PA.Next; // a local owner of h2, so that h1 is not freed while its own field is being reset
  PA.Next.Reset;
  Tmp.Reset;     // h2 dies, and with its field Next the last owner of h1
  C.Reset;
  Check(SafeLiveCount = 0, 'cycle: nothing alive after the cycle is broken');
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
  P := TDeferProbe.Create; // UNSAFE: the probe of the defer test lives to the end of the program
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
  Run('OwnedCopyCaughtInDebug', @OwnedCopyCaughtInDebug, '~k1~k');
  Run('OwnedException', @OwnedException, '~d');
  Run('SharedAndWeak', @SharedAndWeak, '~e');
  Run('InterfacedRejected', @InterfacedRejected, '');
  Run('Slices', @Slices, '');
  Run('ArenaScope', @ArenaScope, '~z~y~x~w');
  Run('ArenaRefAfterFreeAll', @ArenaRefAfterFreeAll, '~g2~g1~g4~g3');

  Run('Defers', @Defers, '');
  Run('SharedCycleReported', @SharedCycleReported, '~h2~h1~h3');
  Run('Leaks', @Leaks, '~leak');
  Run('DeferFailureIsCounted', @DeferFailureIsCounted, '');

  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
