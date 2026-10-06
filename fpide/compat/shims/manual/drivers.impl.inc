type
  TWordRec = packed record
    Lo, Hi: Byte;
  end;

procedure MoveChar(var Dest; C: Char; Attr: Byte; Count: Word);
var
  I: Word;
  P: PWord;
begin
  for I := 1 to Count do
  begin
    P := @TWordArray(Dest)[I - 1];
    if Attr <> 0 then
      TWordRec(P^).Hi := Attr;
    if Ord(C) <> 0 then
      TWordRec(P^).Lo := Byte(C);
  end;
end;

procedure MoveStr(var Dest; const Str: String; Attr: Byte);
var
  I: Word;
  P: PWord;
begin
  for I := 1 to Length(Str) do
  begin
    P := @TWordArray(Dest)[I - 1];
    if Attr <> 0 then
      TWordRec(P^).Hi := Attr;
    TWordRec(P^).Lo := Byte(Str[I]);
  end;
end;

procedure MoveCStr(var Dest; const Str: String; Attrs: Word);
var
  B: Byte;
  I, J: Word;
  P: PWord;
  A: Word;
begin
  A := Attrs;
  J := 0;
  for I := 1 to Length(Str) do
  begin
    if Str[I] <> '~' then
    begin
      P := @TWordArray(Dest)[J];
      if Lo(A) <> 0 then
        TWordRec(P^).Hi := Lo(A);
      TWordRec(P^).Lo := Byte(Str[I]);
      Inc(J);
    end
    else
    begin
      B := Hi(A);
      TWordRec(A).Hi := Lo(A);
      TWordRec(A).Lo := B;
    end;
  end;
end;

procedure MoveBuf(var Dest, Source; Attr: Byte; Count: Word);
var
  I: Word;
  P: PWord;
  S: PByte;
begin
  S := @Source;
  for I := 1 to Count do
  begin
    P := @TWordArray(Dest)[I - 1];
    if Attr <> 0 then
      TWordRec(P^).Hi := Attr;
    TWordRec(P^).Lo := S^;
    Inc(S);
  end;
end;

function GetDosTicks: LongInt;
begin
  { 1 DOS tick ≈ 55 ms }
  Result := LongInt(ClockMs div 55);
end;

procedure FormatStr(var Result: String; const Format: String; var Params);
type
  TLongArray = array[0..0] of PtrInt;
  PShort = ^ShortString;
var
  W, ResultLength: Integer;
  FormatIndex, Justify, Wth: Byte;
  Fill: Char;
  S: String;

  function LongToStr(L: LongInt; Radix: Byte): String;
  const
    HexChars: array[0..15] of Char =
      ('0', '1', '2', '3', '4', '5', '6', '7',
       '8', '9', 'A', 'B', 'C', 'D', 'E', 'F');
  var
    I: LongInt;
    T: String;
    Sign: String[1];
  begin
    if L < 0 then
    begin
      Sign := '-';
      L := Abs(L);
    end
    else
      Sign := '';
    T := '';
    repeat
      I := L mod Radix;
      T := HexChars[I] + T;
      L := L div Radix;
    until L = 0;
    LongToStr := Sign + T;
  end;

  procedure HandleParameter(I: LongInt);
  begin
    while FormatIndex <= Length(Format) do
    begin
      if ResultLength >= High(Result) then
        Exit;
      while (FormatIndex <= Length(Format)) and (Format[FormatIndex] <> '%') do
      begin
        Result[ResultLength + 1] := Format[FormatIndex];
        Inc(ResultLength);
        Inc(FormatIndex);
      end;
      if (FormatIndex < Length(Format)) and (Format[FormatIndex] = '%') then
      begin
        Fill := ' ';
        Justify := 0;
        Wth := 0;
        Inc(FormatIndex);
        if Format[FormatIndex] = '0' then
          Fill := '0';
        if Format[FormatIndex] = '-' then
        begin
          Justify := 1;
          Inc(FormatIndex);
        end;
        while (FormatIndex <= Length(Format)) and
              (Format[FormatIndex] >= '0') and (Format[FormatIndex] <= '9') do
        begin
          Wth := Wth * 10 + Ord(Format[FormatIndex]) - Ord('0');
          Inc(FormatIndex);
        end;
        if (FormatIndex <= Length(Format)) and (Format[FormatIndex] = '#') then
        begin
          Inc(FormatIndex);
          HandleParameter(Wth);
        end;
        if FormatIndex <= Length(Format) then
        begin
          case Format[FormatIndex] of
            '%':
              begin
                S := '%';
                Inc(FormatIndex);
                Move(S[1], Result[ResultLength + 1], 1);
                Inc(ResultLength, Length(S));
                Continue;
              end;
            'c': S := Char(TLongArray(Params)[I]);
            'd': S := LongToStr(TLongArray(Params)[I], 10);
            's': S := PShort(Pointer(TLongArray(Params)[I]))^;
            'x': S := LongToStr(TLongArray(Params)[I], 16);
          end;
          Inc(FormatIndex);
          if Wth > 0 then
          begin
            if Length(S) > Wth then
            begin
              if Justify = 1 then
                S := Copy(S, Length(S) - Wth + 1, Wth)
              else
                S := Copy(S, 1, Wth);
            end
            else if Justify = 1 then
              while Length(S) < Wth do
                S := S + Fill
            else
              while Length(S) < Wth do
                S := Fill + S;
          end;
          W := Length(S);
          if W + ResultLength + 1 > High(Result) then
            W := High(Result) - ResultLength;
          if W > 0 then
            Move(S[1], Result[ResultLength + 1], W);
          Inc(ResultLength, W);
          Inc(I);
        end;
      end;
    end;
  end;

begin
  ResultLength := 0;
  FormatIndex := 1;
  HandleParameter(0);
  Result[0] := Chr(ResultLength);
end;


procedure GetKeyEvent(var Event: TEvent);
begin
  TvSys.PollEvent(0, Event);
  if Event.What <> evKeyDown then
    ClearEvent(Event);
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

procedure GiveUpTimeSlice;
begin
  ThreadSwitch;
end;

procedure ShowMouse;
begin
end;

procedure HideMouse;
begin
end;
