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

{ The slots become an array of const for TvFormat.FormatStr: each % item of Format is written again as an item of
  SysUtils.Format with its argument. What Format cannot write the same way is passed as text: %c as a string, %x and %X
  as the digits (Format has no lower case hex and fills hex with at most 31 zeros), an unknown item as itself. }
procedure FormatStr(var Result: String; const Format: String; var Params);
type
  TSlots = array[0..(MaxInt div SizeOf(PtrInt)) - 1] of PtrInt;
var
  Slots: ^TSlots;
  Next, I, Start, Width, N: Integer;
  Left, Zero: Boolean;
  Conv: Char;
  Fmt: AnsiString;
  Args: array of TVarRec;
  Texts: array of ShortString;
  Nums: array of Int64;
  V: LongInt;
  P: PShortString;
  Hex: AnsiString;

  function Take: PtrInt;
  begin
    Result := Slots^[Next];
    Inc(Next);
  end;

  function Literal(const S: AnsiString): AnsiString;
  begin
    Result := StringReplace(S, '%', '%%', [rfReplaceAll]);
  end;

  procedure AddText(const S: ShortString);
  begin
    Texts[N] := S;
    Args[N].VType := vtString;
    Args[N].VString := @Texts[N];
    Inc(N);
  end;

  procedure AddNum(X: Int64);
  begin
    Nums[N] := X;
    Args[N].VType := vtInt64;
    Args[N].VInt64 := @Nums[N];
    Inc(N);
  end;

  { the item %[-][width]Spec; Format fills at most 255 characters, the rest of a wider item is a literal text of spaces }
  procedure Item(const Spec: ShortString);
  var
    W: Integer;
  begin
    W := Width;
    if W > 255 then
      W := 255;
    if not Left then
      Fmt := Fmt + StringOfChar(' ', Width - W);
    Fmt := Fmt + '%';
    if Left then
      Fmt := Fmt + '-';
    if W > 0 then
      Fmt := Fmt + IntToStr(W);
    Fmt := Fmt + Spec;
    if Left then
      Fmt := Fmt + StringOfChar(' ', Width - W);
  end;

begin
  Slots := @Params;
  Next := 0;
  N := 0;
  SetLength(Args, Length(Format));
  SetLength(Texts, Length(Format));
  SetLength(Nums, Length(Format));
  Fmt := '';
  I := 1;
  while I <= Length(Format) do
  begin
    if Format[I] <> '%' then
    begin
      Fmt := Fmt + Format[I];
      Inc(I);
      Continue;
    end;
    Start := I;
    Inc(I);
    Left := (I <= Length(Format)) and (Format[I] = '-');
    if Left then
      Inc(I);
    Zero := (I <= Length(Format)) and (Format[I] = '0');
    if Zero then
      Inc(I);
    Zero := Zero and not Left;
    Width := 0;
    while (I <= Length(Format)) and (Format[I] in ['0'..'9']) do
    begin
      if Width < 1000 then
        Width := Width * 10 + Ord(Format[I]) - Ord('0');
      Inc(I);
    end;
    if I > Length(Format) then
    begin
      Fmt := Fmt + Literal(Copy(Format, Start, MaxInt));
      Break;
    end;
    Conv := Format[I];
    Inc(I);
    case Conv of
      '%':
        Fmt := Fmt + '%%';
      's':
        begin
          P := PShortString(Pointer(Take));
          if P = nil then
            AddText('')
          else
            AddText(P^);
          Item('s');
        end;
      'c':
        begin
          AddText(Chr(Byte(Take)));
          Item('s');
        end;
      'd', 'u':
        begin
          if Conv = 'd' then
          begin
            V := LongInt(Take);
            AddNum(V);
          end
          else
          begin
            V := 0;
            AddNum(LongWord(Take));
          end;
          if Zero and (Width > 0) then
          begin
            if V < 0 then
              Fmt := Fmt + '%.' + IntToStr(Width - 1) + 'd'
            else
              Fmt := Fmt + '%.' + IntToStr(Width) + 'd';
          end
          else
            Item('d');
        end;
      'x', 'X':
        begin
          Hex := IntToHex(LongWord(Take), 1);
          if Conv = 'x' then
            Hex := LowerCase(Hex);
          if Zero and (Length(Hex) < Width) then
            Hex := StringOfChar('0', Width - Length(Hex)) + Hex;
          AddText(Hex);
          if Zero then
            Fmt := Fmt + '%s'
          else
            Item('s');
        end;
    else
      Fmt := Fmt + Literal(Copy(Format, Start, I - Start));
    end;
  end;
  SetLength(Args, N);
  Result := TvFormat.FormatStr(Fmt, Args);
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
