{ R20: the quarantine of freed class objects (SAFE_DEBUG, SPEC §6, §24.9 decision 4a).
  Built without options; the checks are switched on at run time (SafeDebugChecks := True), as in the other tests.
  Exit code = number of failed checks. }
program test_r20;

{$mode objfpc}{$H+}

uses
  SysUtils, Safe;

type
  TShape = class
  public
    Name: string;
    Sides: Integer;
    constructor Create(const AName: string; ASides: Integer);
    destructor Destroy; override;
    function Describe: string; virtual;
    procedure Grow; virtual;
  end;

  TShapeBox = specialize TOwned<TShape>;
  TShapeRef = specialize TShared<TShape>;

  TTiny = class  // an instance of the size of the VMT pointer alone
  public
    procedure Ping; virtual;
  end;
  TTinyBox = specialize TOwned<TTiny>;

var
  Failed: Integer = 0;
  Dtors: Integer = 0;

constructor TShape.Create(const AName: string; ASides: Integer);
begin
  inherited Create;
  Name := AName;
  Sides := ASides;
end;

destructor TShape.Destroy;
begin
  Inc(Dtors);
  inherited Destroy;
end;

function TShape.Describe: string;
begin
  Result := Name + ':' + IntToStr(Sides);
end;

procedure TShape.Grow;
begin
  Inc(Sides);
end;

procedure TTiny.Ping;
begin
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

procedure VirtualCallOnFreed;
var
  B: TShapeBox;
  S: TShape;
  Msg: string;
begin
  B := TShapeBox.Own(TShape.Create('sq', 4));
  S := B.Get; // a borrow
  Check(S.Describe = 'sq:4', 'r20: a live object answers');
  B.Reset;
  Check(Dtors = 1, 'r20: the destructor ran at Reset');
  Msg := '';
  try
    S.Grow;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check((Pos('SAFE-R20', Msg) > 0) and (Pos('TShape', Msg) > 0), 'r20: a virtual call on a freed object raises, naming the class: ' + Msg);
  Msg := '';
  try
    S.Describe;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R20', Msg) > 0, 'r20: a virtual function on a freed object raises');
end;

procedure SecondFree;
var
  B: TShapeBox;
  S: TShape;
  Msg: string;
begin
  B := TShapeBox.Own(TShape.Create('tri', 3));
  S := B.Get;
  B.Reset;
  Msg := '';
  try
    // UNSAFE: the test frees the object a second time on purpose: the quarantine must stop it
    S.Destroy;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R20', Msg) > 0, 'r20: Destroy of a freed object raises (a second free)');
  Msg := '';
  try
    // UNSAFE: the same, through FreeAndNil of SysUtils (TObject.Free calls the virtual Destroy)
    SysUtils.FreeAndNil(S);
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R20', Msg) > 0, 'r20: FreeAndNil of a freed object raises (a second free)');
  Check(Dtors = 2, 'r20: the destructor ran once only');
end;

procedure ClassNameOfFreed;
var
  B: TShapeBox;
  S: TShape;
begin
  B := TShapeBox.Own(TShape.Create('pent', 5));
  S := B.Get;
  B.Reset;
  Check((Pos('SAFE-R20', S.ClassName) = 1) and (Pos('TShape', S.ClassName) > 0),
    'r20: ClassName of a freed object names the poison class: ' + S.ClassName);
  Check(S.ClassType <> TShape, 'r20: ClassType of a freed object is the poison class, not TShape');
end;

procedure FieldsArePoisoned;
var
  B: TShapeBox;
  S: TShape;
  P: System.PByte;
  I: Integer;
  AllPoison: Boolean;
begin
  B := TShapeBox.Own(TShape.Create('hex', 6));
  S := B.Get;
  B.Reset;
  // UNSAFE: the test reads the freed instance on purpose: the quarantine keeps its memory, filled with $DE
  P := System.PByte(S);
  AllPoison := True;
  for I := 2 * SizeOf(System.Pointer) to S.InstanceSize - 1 do // Sides, after Name (managed, finalized)
    if P[I] <> $DE then
      AllPoison := False;
  Check(AllPoison, 'r20: the fields of a freed object are poison, not the old values');
end;

procedure SharedAndTiny;
var
  R: TShapeRef;
  S: TShape;
  T: TTinyBox;
  Q: TTiny;
  Msg: string;
begin
  R := TShapeRef.Share(TShape.Create('sh', 2));
  S := R.Get;
  R.Reset;
  Msg := '';
  try
    S.Grow;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R20', Msg) > 0, 'r20: TShared release is quarantined too');
  T := TTinyBox.Own(TTiny.Create);
  Q := T.Get;
  T.Reset;
  Msg := '';
  try
    Q.Ping;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R20', Msg) > 0, 'r20: an object of the size of the VMT pointer alone is quarantined');
end;

procedure MakeAndFree(I: Integer);
var
  B: TShapeBox;
begin
  B := TShapeBox.Own(TShape.Create('n', I));
  B.Reset;
end;

procedure FillIsConfigurable;
var
  B: TShapeBox;
  S: TShape;
begin
  SafeQuarantineSetFill($5A);
  B := TShapeBox.Own(TShape.Create('fill', 9));
  S := B.Get;
  B.Reset;
  // UNSAFE: the test reads the freed instance on purpose
  Check(System.PByte(S)[2 * SizeOf(System.Pointer)] = $5A, 'r20: the poison byte is configurable');
  SafeQuarantineSetFill($DE);
end;

procedure ArenaIsQuarantined;
var
  A: TArena;
  S: TShape;
  Msg: string;
begin
  A := TArena.Create;
  S := TShape(A.Adopt(TShape.Create('ar', 7)));
  A.FreeAll;
  Msg := '';
  try
    S.Grow;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R20', Msg) > 0, 'r20: TArena.FreeAll is quarantined too');
end;

procedure HeldIsQuarantined;
var
  R: TRegion;
  S: TShape;
  Msg: string;
begin
  R := TRegion.Create;
  R.Hold(S, TShape.Create('held', 8));
  R.Release;
  Msg := '';
  try
    S.Grow;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R20', Msg) > 0, 'r20: a held object of a region is quarantined too');
end;

procedure BoundFreesTheOldest;
var
  I: Integer;
begin
  SafeQuarantineSetLimits(8, 1 shl 20);
  Check(SafeQuarantineCount = 0, 'r20: changing the limits flushes the quarantine');
  for I := 1 to 20 do
    MakeAndFree(I);
  Check(SafeQuarantineCount = 8, 'r20: the count bound holds: 8 objects wait, the older ones left');
  SafeQuarantineSetLimits(1000, 1);
  for I := 1 to 20 do
    MakeAndFree(I);
  Check(SafeQuarantineCount <= 1, 'r20: the byte bound holds');
  SafeQuarantineSetLimits(4096, 16 * 1024 * 1024);
  SafeQuarantineFlush;
  Check(SafeQuarantineCount = 0, 'r20: SafeQuarantineFlush gives everything back');
end;

procedure ManyFrees;
var
  I: Integer;
begin
  for I := 1 to 20000 do
    MakeAndFree(I);
  Check(SafeQuarantineCount = 4096, 'r20: 20000 frees leave the 4096 newest in the quarantine');
end;

procedure ChecksOff;
var
  N: SizeInt;
begin
  SafeDebugChecks := False;
  N := SafeQuarantineCount;
  MakeAndFree(1);
  Check(SafeQuarantineCount = N, 'r20: with the checks off nothing enters the quarantine');
  SafeDebugChecks := True;
end;

begin
  SafeDebugChecks := True;
  VirtualCallOnFreed;
  SecondFree;
  ClassNameOfFreed;
  FieldsArePoisoned;
  SharedAndTiny;
  FillIsConfigurable;
  ArenaIsQuarantined;
  HeldIsQuarantined;
  ChecksOff;
  BoundFreesTheOldest;
  ManyFrees;
  SafeQuarantineFlush;
  try
    SafeCheckNoLeaks;
    Check(True, 'r20: no leak: SafeCheckNoLeaks passes');
  except
    on E: ESafety do Check(False, 'r20: no leak: ' + E.Message);
  end;
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
