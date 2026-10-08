{ FV Word-cell draw buffer (BIOS attr in hi byte) for IDE Draw code.
  tv3 TDrawBuffer is a class; WriteLineW/GetColorW consume these arrays. }
const
  MaxViewWidth = 255;
  { Free Vision name of the Space key (scan code $39, char $20). }
  kbSpaceBar = $3920;

type
  { The draw buffer of the IDE is a row of tv3 cells (UTF-8 text, wide characters take two cells); the FV Word buffer
    (a byte and a BIOS attribute) could not hold more than a code page of 256 characters. MoveChar/MoveStr/MoveCStr
    below fill it: the strings are UTF-8, a character that is not valid UTF-8 is a byte of the code page. }
  TFVDrawBuffer = array[0..MaxViewWidth - 1] of TScreenCell;
  TWordArray = array[0..MaxViewWidth - 1] of Word;
  PWordArray = ^TWordArray;

procedure MoveChar(var Dest; C: Char; Attr: Byte; Count: Word);
procedure MoveStr(var Dest; const Str: String; Attr: Byte);
procedure MoveCStr(var Dest; const Str: String; Attrs: Word);
procedure MoveBuf(var Dest, Source; Attr: Byte; Count: Word);
{ Str is UTF-8 (or a single byte): the cells of Count characters from C }
procedure MoveFill(var Dest; const Ch: String; Attr: Byte; Count: Word);
{ the character of one cell (a byte of the code page); the attribute is kept }
procedure SetCellChar(var Cell: TScreenCell; C: Char);
{ the character that starts at Str[I] into Cells[P] (two cells if it is wide, none if it combines); P is advanced, the result
  is the number of bytes of Str used }
function PutUtf8(var Cells: TFVDrawBuffer; var P: Integer; const Str: String; I: Integer; Attr: Byte; SetAttr: Boolean): Integer;
{ the BIOS attribute (colour byte) of a cell }
function CellBios(const Cell: TScreenCell): Byte;
procedure SetCellBios(var Cell: TScreenCell; Attr: Byte);

{ ~18.2 Hz tick counter (DOS BIOS style), for idle/timing loops in the IDE. }
function GetDosTicks: LongInt;

{ Result := Format with its % items filled from Params, an array of PtrInt slots (TvFormat.FormatSlots). }
procedure FormatStr(var Result: String; const Format: String; var Params);

{ FV non-blocking keyboard poll: evNothing when no key is pending (the IDE polls for Esc while compiling). }
procedure GetKeyEvent(var Event: TEvent);

{ FV path shortener: keeps the tail of the path with a leading '...' when it is longer than MaxLen bytes. }
function ShrinkPath(Path: string; MaxLen: Integer): string;

{ FV system-error / event-queue lifecycle. tv3 owns the terminal and has no system-event queue, so
  these are no-ops kept for the IDE's suspend/resume code (see docs/known issues in MIGRATION-STATUS). }
{ The terminal mouse pointer is always shown; kept for the IDE's screen hand-over code. }
procedure ShowMouse;
procedure HideMouse;
procedure GetSystemEvent(var Event: TEvent);
procedure InitEvents;
procedure DoneEvents;
procedure InitSysError;
procedure DoneSysError;

var
  { Number of mouse buttons (FV: set by InitMouse; 0 = no mouse). }
  ButtonCount: Byte = 0;
  { Set by a Ctrl-Break handler; the IDE clears it before a compile. tv3 has no such handler yet. }
  CtrlBreakHit: Boolean = False;
  { Cell coordinates of the mouse (updated by the IDE when it sees mouse events). }
  MouseWhere: TPoint;
  { Legacy pixel coordinates (FV linux mouse); idle code does shr 3 → cells. }
  MouseWhereX, MouseWhereY: LongInt;
  { FV mouse prefs (INI / Mouse options dialog). }
  DoubleDelay: Word = 8;
  MouseReverse: Boolean = False;
