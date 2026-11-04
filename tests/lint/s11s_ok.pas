// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11s: TShared of a frozen class and of a class marked // sync: goes to tasks and channels. }
unit s11s_ok;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TConfig = class
  private
    FName: String;
    FLimits: array of Integer;
  public
    constructor Create(const AName: String; const N: Integer);
    function Name: String;
  end;

  // sync: FCount changes only through InterlockedIncrement
  TCounter = class
  private
    FCount: Longint;
  public
    procedure Add;
  end;

  TSharedConfig = specialize TShared<TConfig>;
  TSharedCounter = specialize TShared<TCounter>;
  TConfigChan = specialize TChan<TSharedConfig>;

  TWorker = class(TTask)
  private
    FConfig: TSharedConfig;
    FCounter: TSharedCounter;
  public
    procedure Run; override;
  end;

implementation

constructor TConfig.Create(const AName: String; const N: Integer);
begin
  inherited Create;
  FName := AName;
  SetLength(FLimits, N);
end;

function TConfig.Name: String;
begin
  Result := FName;
end;

procedure TCounter.Add;
begin
  InterlockedIncrement(FCount);
end;

procedure TWorker.Run;
begin
  FCounter.Get.Add;
end;

end.
