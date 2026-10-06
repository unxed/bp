{ ASCIITab for fpide on tv3 classes. MIT. }
{$mode objfpc}{$H-}
unit ASCIITab;

interface

uses
  SysUtils, TvGeom, TvEvents, TvKeys, TvViews, TvWindow, TvDrawBuf, TvColors;

type
  TTable = class(TView)
  public
    AsciiChar: Byte;
    constructor Create(const Bounds: TRect); reintroduce;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
  end;
  PTable = TTable;

  TReport = class(TView)
  public
    AsciiChar: Byte;
    constructor Create(const Bounds: TRect); reintroduce;
    procedure Draw; override;
  end;
  PReport = TReport;

  TASCIIChart = class(TWindow)
  public
    Report: TReport;
    Table: TTable;
    constructor Create; reintroduce;
    procedure HandleEvent(var Event: TEvent); override;
  end;
  PASCIIChart = TASCIIChart;
  PFPAsciiChart = TASCIIChart;

var
  AsciiTableCommandBase: Word = 910;

procedure RegisterASCIITab;

implementation

constructor TTable.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  AsciiChar := 0;
  EventMask := EventMask or evKeyboard or evMouseDown;
end;

procedure TTable.Draw;
var
  B: TDrawBuffer;
  X, Y, Ch: Integer;
  C: TAttrPair;
begin
  C := GetColor(1);
  B := TDrawBuffer.Create(Size.X);
  for Y := 0 to Size.Y - 1 do
  begin
    B.MoveChar(0, Ord(' '), C.Lo, Size.X);
    for X := 0 to Pred(Size.X) do
    begin
      Ch := Y * 32 + X;
      { the Unicode characters U+0000..U+00FF (the editor is UTF-8); the control characters of the first 32 are
        shown by their symbols, the C1 controls U+0080..U+009F as a dot }
      if Ch < 128 then
        B.MoveChar(X, Ch, C.Lo, 1)
      else if Ch < 160 then
        B.MoveChar(X, Ord('.'), C.Lo, 1)
      else if Ch <= 255 then
        B.MoveStrS(X, Chr($C0 or (Ch shr 6)) + Chr($80 or (Ch and $3F)), C.Lo);
    end;
    WriteLineD(0, Y, Size.X, 1, B);
  end;
  B.Free;
end;

procedure TTable.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What = evMouseDown then
  begin
    AsciiChar := Byte((Event.Where.Y - Origin.Y) * 32 + (Event.Where.X - Origin.X));
    ClearEvent(Event);
  end
  else if Event.What = evKeyDown then
  begin
    case Event.KeyCode of
      kbLeft: if AsciiChar > 0 then Dec(AsciiChar);
      kbRight: if AsciiChar < 255 then Inc(AsciiChar);
      kbUp: if AsciiChar >= 32 then Dec(AsciiChar, 32);
      kbDown: if AsciiChar <= 223 then Inc(AsciiChar, 32);
    else
      ;
    end;
    ClearEvent(Event);
  end;
end;

constructor TReport.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  AsciiChar := 0;
end;

procedure TReport.Draw;
var
  B: TDrawBuffer;
  C: TAttrPair;
  S: ShortString;
begin
  B := TDrawBuffer.Create(Size.X);
  C := GetColor(1);
  B.MoveChar(0, Ord(' '), C.Lo, Size.X);
  S := ShortString(Format(' Char: #%d ', [AsciiChar]));
  B.MoveStrS(0, S, C.Lo);
  WriteLineD(0, 0, Size.X, 1, B);
  B.Free;
end;

constructor TASCIIChart.Create;
var
  R: TRect;
begin
  R.Assign(0, 0, 34, 12);
  inherited Create(R, 'ASCII Table', wnNoNumber);
  R.Assign(1, 1, 33, 9);
  Table := TTable.Create(R);
  Insert(Table);
  R.Assign(1, 9, 33, 11);
  Report := TReport.Create(R);
  Insert(Report);
end;

procedure TASCIIChart.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Assigned(Table) and Assigned(Report) then
  begin
    Report.AsciiChar := Table.AsciiChar;
    Report.DrawView;
  end;
end;

procedure RegisterASCIITab;
begin
end;

end.
