type
  TWordRec = packed record
    Lo, Hi: Byte;
  end;

type
  PFVCells = ^TFVDrawBuffer;

function FVAttr(Attr: Byte): TColorAttr;
begin
  Result := CellFromBIOS(Word(Attr) shl 8).Attribute;
end;

procedure SetCellChar(var Cell: TScreenCell; C: Char);
begin
  ScInitChar(Cell.Character, Byte(C));
end;

function CellBios(const Cell: TScreenCell): Byte;
begin
  Result := AttrAsBIOSByte(Cell.Attribute);
end;

procedure SetCellBios(var Cell: TScreenCell; Attr: Byte);
begin
  Cell.Attribute := FVAttr(Attr);
end;

{ writes the character that starts at Str[I] into Cells[P..] (a wide one takes two cells, a combining one none);
  returns the number of bytes used; P is advanced }
function PutUtf8(var Cells: TFVDrawBuffer; var P: Integer; const Str: String; I: Integer; Attr: Byte; SetAttr: Boolean): Integer;
var
  CP: LongWord;
  Used, W: Integer;
  A: TColorAttr;
begin
  Result := 1;
  if P > High(Cells) then
    Exit;
  if SetAttr then
    A := FVAttr(Attr);
  if (Byte(Str[I]) < $80) or (not Utf8Enabled) or
     (not Utf8Decode(@Str[I], Length(Str) - I + 1, CP, Used)) or (Used <= 1) then
  begin
    ScInitChar(Cells[P].Character, Byte(Str[I]));
    if SetAttr then Cells[P].Attribute := A;
    Inc(P);
    Exit;
  end;
  Result := Used;
  W := CharWidth(CP);
  if W <= 0 then
  begin
    { a combining character goes onto the cell before }
    if P > 0 then
      ScAppendZeroWidth(Cells[P - 1].Character, @Str[I], Used);
    Exit;
  end;
  if (W >= 2) and (P + 1 > High(Cells)) then
    W := 1;
  ScInitText(Cells[P].Character, @Str[I], Used, W >= 2);
  if SetAttr then Cells[P].Attribute := A;
  Inc(P);
  if W >= 2 then
  begin
    ScInitWideTrail(Cells[P].Character);
    if SetAttr then Cells[P].Attribute := A;
    Inc(P);
  end;
end;

procedure MoveChar(var Dest; C: Char; Attr: Byte; Count: Word);
var
  I: Word;
  Cells: PFVCells;
begin
  Cells := @Dest;
  for I := 0 to Count - 1 do
  begin
    if Attr <> 0 then
      Cells^[I].Attribute := FVAttr(Attr);
    if Ord(C) <> 0 then
      ScInitChar(Cells^[I].Character, Byte(C));
  end;
end;

procedure MoveFill(var Dest; const Ch: String; Attr: Byte; Count: Word);
var
  I, P: Integer;
  Cells: PFVCells;
begin
  Cells := @Dest;
  P := 0;
  if Ch = '' then
    Exit;
  for I := 1 to Count do
    PutUtf8(Cells^, P, Ch, 1, Attr, Attr <> 0);
end;

procedure MoveStr(var Dest; const Str: String; Attr: Byte);
var
  I, P: Integer;
  Cells: PFVCells;
begin
  Cells := @Dest;
  P := 0;
  I := 1;
  while I <= Length(Str) do
    Inc(I, PutUtf8(Cells^, P, Str, I, Attr, Attr <> 0));
end;

procedure MoveCStr(var Dest; const Str: String; Attrs: Word);
var
  B: Byte;
  I, P: Integer;
  A: Word;
  Cells: PFVCells;
begin
  Cells := @Dest;
  A := Attrs;
  P := 0;
  I := 1;
  while I <= Length(Str) do
  begin
    if Str[I] <> '~' then
      Inc(I, PutUtf8(Cells^, P, Str, I, Lo(A), Lo(A) <> 0))
    else
    begin
      B := Hi(A);
      TWordRec(A).Hi := Lo(A);
      TWordRec(A).Lo := B;
      Inc(I);
    end;
  end;
end;

procedure MoveBuf(var Dest, Source; Attr: Byte; Count: Word);
var
  I: Word;
  S: PByte;
  Cells: PFVCells;
begin
  Cells := @Dest;
  S := @Source;
  for I := 0 to Count - 1 do
  begin
    if Attr <> 0 then
      Cells^[I].Attribute := FVAttr(Attr);
    ScInitChar(Cells^[I].Character, S^);
    Inc(S);
  end;
end;

function GetDosTicks: LongInt;
begin
  { 1 DOS tick ≈ 55 ms }
  Result := LongInt(ClockMs div 55);
end;

procedure FormatStr(var Result: String; const Format: String; var Params);
begin
  FormatSlots(Result, Format, Params);
end;


procedure GetKeyEvent(var Event: TEvent);
begin
  TvSys.PollKeyEvent(Event);
end;

function ShrinkPath(Path: string; MaxLen: Integer): string;
var
  Cut: Integer;
begin
  if Length(Path) <= MaxLen then
  begin
    ShrinkPath := Path;
    Exit;
  end;
  if MaxLen < 4 then
    MaxLen := 4;
  Cut := Length(Path) - (MaxLen - 3) + 1;
  { do not start the tail in the middle of a UTF-8 sequence }
  while (Cut <= Length(Path)) and ((Byte(Path[Cut]) and $C0) = $80) do
    Inc(Cut);
  ShrinkPath := '...' + Copy(Path, Cut, 255);
end;

procedure GetSystemEvent(var Event: TEvent);
begin
  ClearEvent(Event);
end;

procedure InitEvents;
begin
end;

procedure DoneEvents;
begin
end;

procedure InitSysError;
begin
end;

procedure DoneSysError;
begin
end;


procedure ShowMouse;
begin
end;

procedure HideMouse;
begin
end;
