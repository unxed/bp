{ FV Word-cell draw buffer (BIOS attr in hi byte) for IDE Draw code.
  tv3 TDrawBuffer is a class; WriteLineW/GetColorW consume these arrays. }
const
  MaxViewWidth = 255;
  { Free Vision name of the Space key (scan code $39, char $20). }
  kbSpaceBar = $3920;

type
  TFVDrawBuffer = array[0..MaxViewWidth - 1] of Word;
  TWordArray = array[0..MaxViewWidth - 1] of Word;
  PWordArray = ^TWordArray;

procedure MoveChar(var Dest; C: Char; Attr: Byte; Count: Word);
procedure MoveStr(var Dest; const Str: String; Attr: Byte);
procedure MoveCStr(var Dest; const Str: String; Attrs: Word);
procedure MoveBuf(var Dest, Source; Attr: Byte; Count: Word);

{ ~18.2 Hz tick counter (DOS BIOS style), for idle/timing loops in the IDE. }
function GetDosTicks: LongInt;

{ FV printf-style formatter: Params is an array of PtrInt (c/d/s/x). }
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
{ Yield the CPU while the IDE is idle. }
procedure GiveUpTimeSlice;

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
