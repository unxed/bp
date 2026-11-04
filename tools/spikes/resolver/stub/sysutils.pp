{ SPDX-License-Identifier: MIT }
{ A declaration stub for the spike resolver: only what the modules of this repository use. }
unit sysutils;
{$mode objfpc}{$H+}
interface
type
  Exception = class(TObject)
  private
    FMessage: String;
  public
    constructor Create(const Msg: String); virtual;
    constructor CreateFmt(const Msg: String; const Args: array of const); virtual;
    property Message: String read FMessage write FMessage;
  end;
  ExceptClass = class of Exception;
  TReplaceFlags = set of (rfReplaceAll, rfIgnoreCase);
  TStringArray = array of String;
  TSysCharSet = set of AnsiChar;
  EAccessViolation = class(Exception);
  ERangeError = class(Exception);
  EConvertError = class(Exception);
function IntToStr(Value: Int64): String; external;
function StringReplace(const S, OldPattern, NewPattern: String; Flags: TReplaceFlags): String; external;
function ExtractFileName(const F: String): String; external;
function ExtractFilePath(const F: String): String; external;
function ChangeFileExt(const F, E: String): String; external;
function FileExists(const F: String): Boolean; external;
function GetEnvironmentVariable(const N: String): String; external;
function FloatToStr(V: Double): String; external;
function BoolToStr(B: Boolean; UseBoolStrs: Boolean = False): String; external;
function StrToInt(const S: String): LongInt; external;
function CompareText(const A, B: String): LongInt; external;
function SameText(const A, B: String): Boolean; external;
function Format(const Fmt: String; const Args: array of const): String; external;
function StrToIntDef(const S: String; Default: LongInt): LongInt; external;
function TryStrToInt(const S: String; out I: LongInt): Boolean; external;
procedure FreeAndNil(var Obj); external;
function Trim(const S: String): String; external;
function UpperCase(const S: String): String; external;
function LowerCase(const S: String): String; external;
procedure Sleep(ms: LongWord); external;
function GetTickCount64: QWord; external;
implementation
constructor Exception.Create(const Msg: String);
begin
end;
constructor Exception.CreateFmt(const Msg: String; const Args: array of const);
begin
end;
end.
