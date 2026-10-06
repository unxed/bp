{ Outline for fpide on tv3 classes. Port of Free Vision packages/fv/src/outline.pas
  (object → class; nested callbacks instead of codepointer). }
{$mode objfpc}{$H-}
{$modeswitch nestedprocvars}
unit Outline;

interface

uses
  Objects, Drivers, Views, WUtf8;

type
  PNode = ^TNode;
  TNode = record
    Next: PNode;
    Text: PString;
    ChildList: PNode;
    Expanded: Boolean;
  end;

  TOutlineAction = function(Cur: Pointer; Level, Position: Sw_Integer;
    Lines: LongInt; Flags: Word): Boolean is nested;

  TOutlineViewer = class;
  POutlineViewer = TOutlineViewer;
  TOutlineViewer = class(TScroller)
    Foc: Sw_Integer;
    constructor Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar);
    procedure Adjust(Node: Pointer; Expand: Boolean); virtual;
    function CreateGraph(Level: Integer; Lines: LongInt; Flags: Word;
      LevWidth, EndWidth: Integer; const Chars: String): String;
    procedure Draw; override;
    procedure ExpandAll(Node: Pointer);
    function FirstThat(Test: TOutlineAction): Pointer;
    procedure Focused(I: Sw_Integer); virtual;
    procedure ForEach(Action: TOutlineAction);
    function GetChild(Node: Pointer; I: Sw_Integer): Pointer; virtual;
    function GetGraph(Level: Integer; Lines: LongInt; Flags: Word): String;
    function GetNode(I: Sw_Integer): Pointer; virtual;
    function GetNumChildren(Node: Pointer): Sw_Integer; virtual;
    function GetPalette: TPalette; override;
    function GetRoot: Pointer; virtual;
    function GetText(Node: Pointer): String; virtual;
    procedure HandleEvent(var Event: TEvent); override;
    function HasChildren(Node: Pointer): Boolean; virtual;
    function IsExpanded(Node: Pointer): Boolean; virtual;
    function IsSelected(I: Sw_Integer): Boolean; virtual;
    procedure Selected(I: Sw_Integer); virtual;
    procedure SetState(AState: Word; Enable: Boolean); override;
    procedure Update; override;
  private
    procedure SetFocusItem(AFocus: Sw_Integer);
    function DoRecurse(Action: TOutlineAction; StopIfFound: Boolean): Pointer;
  end;

  TOutline = class;
  POutline = TOutline;
  TOutline = class(TOutlineViewer)
    Root: PNode;
    constructor Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar;
      ARoot: PNode);
    procedure Adjust(Node: Pointer; Expand: Boolean); override;
    function GetChild(Node: Pointer; I: Sw_Integer): Pointer; override;
    function GetNumChildren(Node: Pointer): Sw_Integer; override;
    function GetRoot: Pointer; override;
    function GetText(Node: Pointer): String; override;
    function HasChildren(Node: Pointer): Boolean; override;
    function IsExpanded(Node: Pointer): Boolean; override;
    destructor Destroy; override;
  end;

const
  ovExpanded = $1;
  ovChildren = $2;
  ovLast     = $4;
  COutlineViewer = #6#7#8#8; { CScroller + #8#8 }

function NewNode(const AText: String; AChildren, ANext: PNode): PNode;
procedure DisposeNode(Node: PNode);

implementation

function Space(N: Integer): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to N do
    Result := Result + ' ';
end;

function NewNode(const AText: String; AChildren, ANext: PNode): PNode;
begin
  New(Result);
  Result^.Next := ANext;
  Result^.Text := PString(NewStr(AText));
  Result^.ChildList := AChildren;
  Result^.Expanded := True;
end;

procedure DisposeNode(Node: PNode);
var
  N: PNode;
begin
  while Node <> nil do
  begin
    DisposeNode(Node^.ChildList);
    DisposeStr(PStr(Node^.Text));
    N := Node^.Next;
    Dispose(Node);
    Node := N;
  end;
end;

constructor TOutlineViewer.Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar);
begin
  inherited Create(Bounds, AHScrollBar, AVScrollBar);
  Foc := 0;
  GrowMode := gfGrowHiX + gfGrowHiY;
end;

procedure TOutlineViewer.Adjust(Node: Pointer; Expand: Boolean);
begin
  Abstract;
end;

function TOutlineViewer.CreateGraph(Level: Integer; Lines: LongInt;
  Flags: Word; LevWidth, EndWidth: Integer; const Chars: String): String;
const
  FillerOrBar   = 0;
  YorL          = 2;
  StraightOrTee = 4;
  Retracted     = 6;
var
  I, J: Byte;
  Graph: String;
begin
  Graph := Space(Level * LevWidth + EndWidth + 1);
  J := 1;
  while Level > 0 do
  begin
    Inc(J);
    if (Lines and 1) <> 0 then
      Graph[J] := Chars[FillerOrBar + 2]
    else
      Graph[J] := Chars[FillerOrBar + 1];
    for I := 1 to LevWidth - 1 do
      Graph[I] := Chars[FillerOrBar + 1];
    J := J + LevWidth - 1;
    Dec(Level);
    Lines := Lines shr 1;
  end;
  Dec(EndWidth);
  if EndWidth > 0 then
  begin
    Inc(J);
    if (Flags and ovLast) <> 0 then
      Graph[J] := Chars[YorL + 2]
    else
      Graph[J] := Chars[YorL + 1];
    Dec(EndWidth);
    if EndWidth > 0 then
    begin
      Dec(EndWidth);
      for I := 1 to EndWidth do
        Graph[I] := Chars[StraightOrTee + 1];
      J := J + EndWidth;
      Inc(J);
      if (Flags and ovChildren) <> 0 then
        Graph[J] := Chars[StraightOrTee + 2]
      else
        Graph[J] := Chars[StraightOrTee + 1];
    end;
    Inc(J);
    if (Flags and ovExpanded) <> 0 then
      Graph[J] := Chars[Retracted + 2]
    else
      Graph[J] := Chars[Retracted + 1];
  end;
  Graph[0] := Char(J);
  Result := Graph;
end;

function TOutlineViewer.DoRecurse(Action: TOutlineAction; StopIfFound: Boolean): Pointer;
var
  Position: Sw_Integer;

  function Recurse(Cur: Pointer; Level: Integer; Lines: LongInt; LastChild: Boolean): Pointer;
  var
    I, ChildCount: Sw_Integer;
    Child: Pointer;
    Flags: Word;
    Children, Expanded, Found: Boolean;
  begin
    Inc(Position);
    Result := nil;
    Children := HasChildren(Cur);
    Expanded := IsExpanded(Cur);
    Flags := 0;
    if (not Children) or Expanded then
      Inc(Flags, ovExpanded);
    if Children and Expanded then
      Inc(Flags, ovChildren);
    if LastChild then
      Inc(Flags, ovLast);
    Found := Action(Cur, Level, Position, Lines, Flags);
    if StopIfFound and Found then
      Result := Cur
    else if Children and Expanded then
    begin
      if not LastChild then
        Lines := Lines or (1 shl Level);
      ChildCount := GetNumChildren(Cur);
      for I := 0 to ChildCount - 1 do
      begin
        Child := GetChild(Cur, I);
        if (Child <> nil) and (Level < 31) then
          Result := Recurse(Child, Level + 1, Lines, I = ChildCount - 1);
        if Result <> nil then
          Break;
      end;
    end;
  end;

var
  R: Pointer;
begin
  Position := -1;
  R := GetRoot;
  if R <> nil then
    Result := Recurse(R, 0, 0, True)
  else
    Result := nil;
end;

procedure TOutlineViewer.Draw;
var
  CNormal, CNormalX, CSelect, CFocus: Byte;
  MaxPos: Sw_Integer;
  B: TFVDrawBuffer;

  function DrawItem(Cur: Pointer; Level, Position: Sw_Integer; Lines: LongInt;
    Flags: Word): Boolean;
  var
    C, I: Byte;
    S, T, G: String;
  begin
    Result := Position >= Delta.Y + Size.Y;
    if (Position < Delta.Y) or Result then
      Exit;
    MaxPos := Position;
    S := GetGraph(Level, Lines, Flags);
    T := GetText(Cur);
    if (Foc = Position) and ((State and sfFocused) <> 0) then
      C := CFocus
    else if IsSelected(Position) then
      C := CSelect
    else if (Flags and ovExpanded) <> 0 then
      C := CNormalX
    else
      C := CNormal;
    G := '';
    for I := 1 to Length(S) do
      case S[I] of
        #1: G := G + '│';
        #2: G := G + '├';
        #3: G := G + '└';
        #4: G := G + '─';
      else
        G := G + S[I];
      end;
    MoveChar(B, ' ', C, Size.X);
    MoveStr(B, U8Copy(G + T, Delta.X, Size.X * 4), C);
    WriteLineC(0, Position - Delta.Y, Size.X, 1, B);
  end;

begin
  CNormal := Lo(GetColorW(4));
  CNormalX := Lo(GetColorW(1));
  CFocus := Lo(GetColorW(2));
  CSelect := Lo(GetColorW(3));
  MaxPos := -1;
  ForEach(@DrawItem);
  MoveChar(B, ' ', CNormal, Size.X);
  WriteLineC(0, MaxPos + 1, Size.X, Size.Y - (MaxPos - Delta.Y), B);
end;

procedure TOutlineViewer.ExpandAll(Node: Pointer);
var
  I: Sw_Integer;
begin
  if HasChildren(Node) then
  begin
    for I := 0 to GetNumChildren(Node) - 1 do
      ExpandAll(GetChild(Node, I));
    Adjust(Node, True);
  end;
end;

function TOutlineViewer.FirstThat(Test: TOutlineAction): Pointer;
begin
  Result := DoRecurse(Test, True);
end;

procedure TOutlineViewer.Focused(I: Sw_Integer);
begin
  Foc := I;
end;

procedure TOutlineViewer.ForEach(Action: TOutlineAction);
begin
  DoRecurse(Action, False);
end;

function TOutlineViewer.GetChild(Node: Pointer; I: Sw_Integer): Pointer;
begin
  Abstract;
  Result := nil;
end;

function TOutlineViewer.GetGraph(Level: Integer; Lines: LongInt; Flags: Word): String;
begin
  { one byte per piece (the graph is made by byte positions): space, vertical bar, tee, corner, horizontal bar, horizontal bar, +, horizontal bar;
    Draw turns #1..#4 into the line-drawing characters of Unicode }
  Result := CreateGraph(Level, Lines, Flags, 3, 3,
    ' ' + #1 + #2 + #3 + #4 + #4 + '+' + #4);
end;

function TOutlineViewer.GetNode(I: Sw_Integer): Pointer;

  function TestPosition(Node: Pointer; Level, Position: Sw_Integer; Lines: LongInt;
    Flags: Word): Boolean;
  begin
    Result := Position = I;
  end;

begin
  Result := FirstThat(@TestPosition);
end;

function TOutlineViewer.GetNumChildren(Node: Pointer): Sw_Integer;
begin
  Abstract;
  Result := 0;
end;

function TOutlineViewer.GetPalette: TPalette;
begin
  Result := MakePalette(COutlineViewer);
end;

function TOutlineViewer.GetRoot: Pointer;
begin
  Abstract;
  Result := nil;
end;

function TOutlineViewer.GetText(Node: Pointer): String;
begin
  Abstract;
  Result := '';
end;

procedure TOutlineViewer.HandleEvent(var Event: TEvent);
var
  Mouse: TPoint;
  Cur: Pointer;
  NewFocus: Sw_Integer;
  Count: Byte;
  Handled, M, MouseDrag: Boolean;
  Graph: String;

  function GraphOfFocus(var GraphStr: String): Pointer;
  var
    LLevel: Sw_Integer;
    LLines: LongInt;
    LFlags: Word;

    function FindFocused(CurN: Pointer; Level, Position: Sw_Integer; Lines: LongInt;
      Flags: Word): Boolean;
    begin
      Result := Position = Foc;
      if Result then
      begin
        LLevel := Level;
        LLines := Lines;
        LFlags := Flags;
      end;
    end;

  begin
    Result := FirstThat(@FindFocused);
    GraphStr := GetGraph(LLevel, LLines, LFlags);
  end;

const
  SkipMouseEvents = 3;
begin
  inherited HandleEvent(Event);
  case Event.What of
    evKeyDown:
      begin
        NewFocus := Foc;
        Handled := True;
        case CtrlToArrow(Event.KeyCode) of
          kbUp, kbLeft: Dec(NewFocus);
          kbDown, kbRight: Inc(NewFocus);
          kbPgDn: Inc(NewFocus, Size.Y - 1);
          kbPgUp: Dec(NewFocus, Size.Y - 1);
          kbCtrlPgUp: NewFocus := 0;
          kbCtrlPgDn: NewFocus := Limit.Y - 1;
          kbHome: NewFocus := Delta.Y;
          kbEnd: NewFocus := Delta.Y + Size.Y - 1;
          kbCtrlEnter, kbEnter: Selected(NewFocus);
        else
          case Event.CharCode of
            Ord('-'), Ord('+'):
              begin
                Adjust(GetNode(NewFocus), Event.CharCode = Ord('+'));
                Update;
              end;
            Ord('*'):
              begin
                ExpandAll(GetNode(NewFocus));
                Update;
              end;
          else
            Handled := False;
          end;
        end;
        if NewFocus < 0 then
          NewFocus := 0;
        if NewFocus >= Limit.Y then
          NewFocus := Limit.Y - 1;
        if Foc <> NewFocus then
          SetFocusItem(NewFocus);
        if Handled then
          ClearEvent(Event);
      end;
    evMouseDown:
      begin
        Count := 1;
        MouseDrag := False;
        NewFocus := Foc;
        repeat
          MakeLocal(Event.Where, Mouse);
          if MouseInView(Event.Where) then
            NewFocus := Delta.Y + Mouse.Y
          else
          begin
            Inc(Count, Byte(Event.What = evMouseAuto));
            if (Count and SkipMouseEvents) = 0 then
            begin
              if Mouse.Y < 0 then
                Dec(NewFocus);
              if Mouse.Y >= Size.Y then
                Inc(NewFocus);
            end;
          end;
          if NewFocus < 0 then
            NewFocus := 0;
          if NewFocus >= Limit.Y then
            NewFocus := Limit.Y - 1;
          if Foc <> NewFocus then
            SetFocusItem(NewFocus);
          M := MouseEvent(Event, evMouseMove + evMouseAuto);
          if M then
            MouseDrag := True;
        until not M;
        if (Event.EventFlags and meDoubleClick) <> 0 then
          Selected(Foc)
        else if not MouseDrag then
        begin
          Cur := GraphOfFocus(Graph);
          if Mouse.X < Length(Graph) then
          begin
            Adjust(Cur, not IsExpanded(Cur));
            Update;
          end;
        end;
      end;
  end;
end;

function TOutlineViewer.HasChildren(Node: Pointer): Boolean;
begin
  Abstract;
  Result := False;
end;

function TOutlineViewer.IsExpanded(Node: Pointer): Boolean;
begin
  Abstract;
  Result := False;
end;

function TOutlineViewer.IsSelected(I: Sw_Integer): Boolean;
begin
  Result := Foc = I;
end;

procedure TOutlineViewer.Selected(I: Sw_Integer);
begin
end;

procedure TOutlineViewer.SetFocusItem(AFocus: Sw_Integer);
begin
  Assert((AFocus >= 0) and (AFocus < Limit.Y));
  Focused(AFocus);
  if AFocus < Delta.Y then
    ScrollTo(Delta.X, AFocus)
  else if AFocus - Size.Y >= Delta.Y then
    ScrollTo(Delta.X, AFocus - Size.Y + 1);
  DrawView;
end;

procedure TOutlineViewer.SetState(AState: Word; Enable: Boolean);
begin
  if (AState and sfFocused) <> 0 then
    DrawView;
  inherited SetState(AState, Enable);
end;

procedure TOutlineViewer.Update;
var
  Count: Sw_Integer;
  MaxWidth: Byte;

  function CheckItem(Cur: Pointer; Level, Position: Sw_Integer; Lines: LongInt;
    Flags: Word): Boolean;
  var
    Width: Word;
  begin
    Inc(Count);
    Width := Length(GetText(Cur)) + Length(GetGraph(Level, Lines, Flags));
    if Width > MaxWidth then
      MaxWidth := Width;
    Result := False;
  end;

begin
  Count := 0;
  MaxWidth := 0;
  ForEach(@CheckItem);
  SetLimit(MaxWidth, Count);
  SetFocusItem(Foc);
end;

constructor TOutline.Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar;
  ARoot: PNode);
begin
  inherited Create(Bounds, AHScrollBar, AVScrollBar);
  Root := ARoot;
  Update;
end;

procedure TOutline.Adjust(Node: Pointer; Expand: Boolean);
begin
  Assert(Node <> nil);
  PNode(Node)^.Expanded := Expand;
end;

function TOutline.GetNumChildren(Node: Pointer): Sw_Integer;
var
  P: PNode;
begin
  Assert(Node <> nil);
  P := PNode(Node)^.ChildList;
  Result := 0;
  while P <> nil do
  begin
    Inc(Result);
    P := P^.Next;
  end;
end;

function TOutline.GetChild(Node: Pointer; I: Sw_Integer): Pointer;
begin
  Assert(Node <> nil);
  Result := PNode(Node)^.ChildList;
  while I <> 0 do
  begin
    Dec(I);
    Result := PNode(Result)^.Next;
  end;
end;

function TOutline.GetRoot: Pointer;
begin
  Result := Root;
end;

function TOutline.GetText(Node: Pointer): String;
begin
  Assert(Node <> nil);
  if PNode(Node)^.Text = nil then
    Result := ''
  else
    Result := PNode(Node)^.Text^;
end;

function TOutline.HasChildren(Node: Pointer): Boolean;
begin
  Assert(Node <> nil);
  Result := PNode(Node)^.ChildList <> nil;
end;

function TOutline.IsExpanded(Node: Pointer): Boolean;
begin
  Assert(Node <> nil);
  Result := PNode(Node)^.Expanded;
end;

destructor TOutline.Destroy;
begin
  DisposeNode(Root);
  inherited Destroy;
end;

end.
