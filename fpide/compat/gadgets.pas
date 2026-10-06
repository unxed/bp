{ Minimal Gadgets for fpide on tv3 classes. MIT. }
{$mode objfpc}{$H-}
unit Gadgets;

interface

uses
  SysUtils, Dos, TvGeom, TvEvents, TvViews, TvDrawBuf, TvScreen, TvColors;

type
  THeapView = class(TView)
  private
    FOldMem: PtrUInt;
    FKb: Boolean;
  public
    constructor Create(const Bounds: TRect); reintroduce;
    { Free Vision: the same view showing the free memory in Kb }
    constructor InitKb(const Bounds: TRect);
    procedure Draw; override;
    procedure Update; virtual;
  end;
  PHeapView = THeapView;

  TClockView = class(TView)
  private
    FLast: string;
  public
    TimeStr: string;
    constructor Create(const Bounds: TRect); reintroduce;
    procedure Draw; override;
    procedure Update; virtual;
  end;
  PClockView = TClockView;

implementation

constructor THeapView.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  FOldMem := 0;
end;

constructor THeapView.InitKb(const Bounds: TRect);
begin
  Create(Bounds);
  FKb := True;
end;

procedure THeapView.Draw;
var
  B: TDrawBuffer;
  S: ShortString;
  C: TAttrPair;
begin
  B := TDrawBuffer.Create(Size.X);
  C := GetColor(1);
  B.MoveChar(0, Ord(' '), C.Lo, Size.X);
  if FKb then
    S := ShortString(Format('%6d', [GetHeapStatus.TotalAllocated div 1024]))
  else
    S := ShortString(Format('%6d', [GetHeapStatus.TotalAllocated]));
  B.MoveStrS(0, S, C.Lo);
  WriteLineD(0, 0, Size.X, 1, B);
  B.Free;
end;

procedure THeapView.Update;
var
  M: PtrUInt;
begin
  M := GetHeapStatus.TotalAllocated;
  if M <> FOldMem then
  begin
    FOldMem := M;
    DrawView;
  end;
end;

constructor TClockView.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  FLast := '';
  TimeStr := '';
end;

procedure TClockView.Draw;
var
  B: TDrawBuffer;
  C: TAttrPair;
begin
  B := TDrawBuffer.Create(Size.X);
  C := GetColor(1);
  B.MoveChar(0, Ord(' '), C.Lo, Size.X);
  B.MoveStrS(0, ShortString(TimeStr), C.Lo);
  WriteLineD(0, 0, Size.X, 1, B);
  B.Free;
end;

procedure TClockView.Update;
var
  H, M, S, Hund: Word;
  T: string;
begin
  GetTime(H, M, S, Hund);
  T := Format('%.2d:%.2d:%.2d', [H, M, S]);
  if T <> FLast then
  begin
    FLast := T;
    TimeStr := T;
    DrawView;
  end;
end;

end.
