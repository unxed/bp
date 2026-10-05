{ FV Word-cell draw buffer (BIOS attr in hi byte) for IDE Draw code.
  tv3 TDrawBuffer is a class; WriteLineW/GetColorW consume these arrays. }
const
  MaxViewWidth = 255;

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

var
  { Cell coordinates of the mouse (updated by the IDE when it sees mouse events). }
  MouseWhere: TPoint;
  { Legacy pixel coordinates (FV linux mouse); idle code does shr 3 → cells. }
  MouseWhereX, MouseWhereY: LongInt;
