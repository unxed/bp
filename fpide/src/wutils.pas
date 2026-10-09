{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit WUtils;

{$mode objfpc}{$H-}
{$modeswitch nestedprocvars}
{$modeswitch autoderef}

interface

uses
{$ifdef Windows}
  windows,
{$endif Windows}
{$ifdef netwlibc}
  libc,
{$else}
  {$ifdef netware}
    nwserv,
  {$endif}
{$endif}

{$ifdef Unix}
  baseunix,
  unix,
{$endif Unix}
  Dos,Objects,TvPath;

const
      kbCtrlGrayPlus         = $9000;
      kbCtrlGrayMinus        = $8e00;
      kbCtrlGrayMul          = $9600;

  TempFirstChar = {$ifndef Unix}'~'{$else}'_'{$endif};
  TempExt       = '.tmp';
  TempNameLen   = 8;

  { Get DirSep and EOL from System unit, instead of redefining 
    here with tons of $ifdefs (KB) }
  DirSep : char = PathSep;
  { the mask that matches every file: "*.*" only matches names with a dot on Unix }
  AllFilesMask = PathAllFiles;
  EOL : String[2] = System.LineEnding;


type
  PByteArray = ^TByteArray;
  TByteArray = array[0..MaxBytes] of byte;
  PWordArray = ^TWordArray;
  TWordArray = array[0..MaxBytes] of Word;

  { A TCollection (the type of the list of a list box) whose items are not written to streams: the views
    that own one write no list. Reading or writing an item is the error peNotRegistered. }
  TUnstoredCollection = class(TCollection)
  protected
    function ReadItem(Ip: ipstream): Pointer; override;
    procedure WriteItem(Item: Pointer; Os: opstream); override;
  end;

  { The same for a sorted list. }
  TUnstoredSortedCollection = class(TSortedCollection)
  protected
    function ReadItem(Ip: ipstream): Pointer; override;
    procedure WriteItem(Item: Pointer; Os: opstream); override;
  end;

  TNoDisposeCollection = class;
  PNoDisposeCollection = TNoDisposeCollection;
  TNoDisposeCollection = class(TNSCollection)
    procedure FreeItem(Item: Pointer); override;
  end;

  TUnsortedStringCollection = class;
  PUnsortedStringCollection = TUnsortedStringCollection;
  { Abbreviation used by whtml/html helpers. }
  PUnsortedStrCollection = PUnsortedStringCollection;
  TUnsortedStrCollection = TUnsortedStringCollection;
  TUnsortedStringCollection = class(TCollection)
    constructor CreateFrom(ALines: TUnsortedStringCollection);
    procedure   Assign(ALines: TUnsortedStringCollection);
    function    At(Index: Sw_Integer): PString;
    procedure   FreeItem(Item: Pointer); override;
    function ReadItem(Ip: ipstream): Pointer; override;
    procedure WriteItem(Item: Pointer; Os: opstream); override;
    procedure   InsertStr(const S: string);
    function StreamableName: ShortString; override;
    class function Build: TStreamable; static;
  end;

  TNulStream = class;
  PNulStream = TNulStream;
  TNulStream = class(TStream)
  private
    Position: Int64;
  public
    constructor Create;
    function    GetPos: Int64; override;
    function    GetSize: Int64; override;
    procedure   Read(var Buf; Count: Longint); override;
    procedure   Seek(Pos: Int64); override;
    procedure   Write(const Buf; Count: Longint); override;
  end;

  TSubStream = class;
  PSubStream = TSubStream;
  TSubStream = class(TStream)
  private
    StartPos: Int64;
    StreamSize: Int64;
    S: TStream;
  public
    constructor Create(AStream: TStream; AStartPos, ASize: Int64);
    function    GetPos: Int64; override;
    function    GetSize: Int64; override;
    procedure   Read(var Buf; Count: Longint); override;
    procedure   Seek(Pos: Int64); override;
    procedure   Write(const Buf; Count: Longint); override;
  end;

  TFastBufStream = class;
  PFastBufStream = TFastBufStream;
  TFastBufStream = class(TBufStream)
  private
    BasePos: Int64;
  public
    constructor Create(const FileName: FNameStr; Mode: Word; Size: Longint);
    procedure   Seek(Pos: Int64); override;
    procedure Readline(var s: string; var linecomplete, hasCR: boolean);
  end;

  TTextCollection = class;
  PTextCollection = TTextCollection;
  TTextCollection = class(TStringCollection)
    function LookUp(const S: string; var Idx: Sw_Integer): string;
    function Compare(Key1, Key2: Pointer): Sw_Integer; override;
  end;

  TIntCollection = class;
  PIntCollection = TIntCollection;
  TIntCollection = class(TNSSortedCollection)
    function  Compare(Key1, Key2: Pointer): Sw_Integer; override;
    procedure FreeItem(Item: Pointer); override;
    procedure Add(Item: PtrInt);
    function  Contains(Item: PtrInt): boolean;
    function  AtInt(Index: Sw_Integer): PtrInt;
  end;

procedure ReadlnFromStream(Stream: TStream; var s: string; var linecomplete, hasCR: boolean);
function EofStream(S: TStream): boolean;
procedure ReadlnFromFile(var f : file; var S:string;
           var linecomplete,hasCR : boolean;
           BreakOnSpacesOnly : boolean);

function Min(A,B: longint): longint;
function Max(A,B: longint): longint;

function CharStr(const C: string; Count: integer): string;
function UpcaseStr(const S: string): string;
function LowCase(C: char): char;
function LowcaseStr(S: string): string;
function RExpand(const S: string; MinLen: byte): string;
function LExpand(const S: string; MinLen: byte): string;
function LTrim(const S: string): string;
function RTrim(const S: string): string;
function Trim(const S: string): string;
function IntToStr(L: longint): string;
function IntToStrL(L: longint; MinLen: sw_integer): string;
function IntToStrZ(L: longint; MinLen: sw_integer): string;
function StrToInt(const S: string): longint;
function StrToCard(const S: string): cardinal;
function FloatToStr(D: Double; Decimals: byte): string;
function FloatToStrL(D: Double; Decimals: byte; MinLen: byte): string;
function GetStr(P: PString): string;
procedure SetStr(var P: PString; const S: string);
function GetPChar(P: PChar): string;
function BoolToStr(B: boolean; const TrueS, FalseS: string): string;
function LExtendString(S: string; MinLen: byte): string;

{ FSplit and FExpand by the rules of the system (those of the Dos unit read '\' as a separator on Unix too);
  ExpandPath also reads a leading '~' as the home directory on Unix }
procedure SplitPath(const S: string; var D: DirStr; var N: NameStr; var E: ExtStr);
function ExpandPath(const S: string): string;
function DirOf(const S: string): string;
function ExtOf(const S: string): string;
function NameOf(const S: string): string;
function NameAndExtOf(const S: string): string;
function DirAndNameOf(const S: string): string;
{ return Dos GetFTime value or -1 if the file does not exist }
function GetFileTime(const FileName: string): longint;
{ copied from compiler global unit }
function GetShortName(const n:string):string;
function GetLongName(const n:string):string;
function TrimEndSlash(const Path: string): string;
function CompleteDir(const Path: string): string;
function GetCurDir: string;
function OptimizePath(Path: string; MaxLen: integer): string;
function CompareText(S1, S2: string): integer;
function ExistsDir(const DirName: string): boolean;
function ExistsFile(const FileName: string): boolean;
function SizeOfFile(const FileName: string): longint;
function DeleteFile(const FileName: string): integer;
function CopyFile(const SrcFileName, DestFileName: string): boolean;
function GenTempFileName: string;

function FormatPath(Path: string): string;
function CompletePath(const Base, InComplete: string): string;
function CompleteURL(const Base, URLRef: string): string;

function EatIO: integer;

function Now: longint;

function FormatDateTimeL(L: longint; const Format: string): string;
function FormatDateTime(const D: DateTime; const Format: string): string;

function MemToStr(var B; Count: byte): string;
procedure StrToMem(S: string; var B);

const LastStrToIntResult : integer = 0;
      LastHexToIntResult : integer = 0;
      LastStrToCardResult : integer = 0;
      LastHexToCardResult : integer = 0;
      UseOldBufStreamMethod : boolean = false;

procedure RegisterWUtils;

Procedure DebugMessage(AFileName, AText : string; ALine, APos : sw_word); // calls DebugMessage

Procedure WUtilsDebugMessage(AFileName, AText : string; ALine, APos : string; nrLine, nrPos : sw_word);

type
  TDebugMessage = procedure(AFileName, AText : string; ALine, APos : String; nrLine, nrPos : sw_word);

Const
  DebugMessageS : TDebugMessage = @WUtilsDebugMessage;

implementation

uses
{$IFDEF OS2}
  DosCalls,
{$ENDIF OS2}
  Strings, Drivers, TvUStr, TvUtf8;

const
   SpaceStr = '                                                            '+
              '                                                            '+
              '                                                            '+
              '                                                            ' ;

{$ifndef NOOBJREG}


{$endif}

function EofStream(S: TStream): boolean;
begin
  EofStream := (S.GetPos >= S.GetSize);
end;

procedure ReadlnFromStream(Stream: TStream; var S: string; var linecomplete, hasCR: boolean);
  var
    c : char;
    i,pos : longint;
  begin
    linecomplete:=false;
    c:=#0;
    i:=0;
    { this created problems for lines longer than 255 characters
      now those lines are cutted into pieces without warning PM }
    { changed implicit 255 to High(S), so it will be automatically extended
      when longstrings eventually become default - Gabor }
    while (not EofStream(Stream)) and (c<>#10) and (i<High(S)) do
     begin
       Stream.Read(c, SizeOf(c));
       if c<>#10 then
        begin
          inc(i);
          s[i]:=c;
        end;
     end;
    { if there was a CR LF then remove the CR Dos newline style }
    if (i>0) and (s[i]=#13) then
      begin
        dec(i);
      end;
    if (c=#13) and (not EofStream(Stream)) then
      Stream.Read(c, SizeOf(c));
    if (i=High(S)) and not EofStream(Stream) then
      begin
        pos:=Stream.getpos;
        Stream.Read(c, SizeOf(c));
        if (c=#13) and not EofStream(Stream) then
          Stream.Read(c, SizeOf(c));
        if c<>#10 then
          Stream.seek(pos);
      end;

    if (c=#10) or EofStream(Stream) then
      linecomplete:=true;
    if (c=#10) then
      hasCR:=true;
    setlength(s,i);  
  end;

procedure ReadlnFromFile(var f : file; var S:string;
           var linecomplete,hasCR : boolean;
           BreakOnSpacesOnly : boolean);
  var
    c : char;
    i,pos,
    lastspacepos,LastSpaceFilePos : longint;
{$ifdef DEBUG}
    filename: string;
{$endif DEBUG}
  begin
    LastSpacePos:=0;
    linecomplete:=false;
    c:=#0;
    i:=0;
    { this created problems for lines longer than 255 characters
      now those lines are cutted into pieces without warning PM }
    { changed implicit 255 to High(S), so it will be automatically extended
      when longstrings eventually become default - Gabor }
    while (not eof(f)) and (c<>#10) and (i<High(S)) do
     begin
       system.blockread(f,c,sizeof(c));
       if c<>#10 then
        begin
          inc(i);
          s[i]:=c;
        end;
       if BreakOnSpacesOnly and (c=' ') then
         begin
           LastSpacePos:=i;
           LastSpaceFilePos:=system.filepos(f);
         end;
     end;
    { if there was a CR LF then remove the CR Dos newline style }
    if (i>0) and (s[i]=#13) then
      begin
        dec(i);
      end;
    if (c=#13) and (not eof(f)) then
      system.blockread(f,c,sizeof(c));
    if (i=High(S)) and not eof(f) then
      begin
        pos:=system.filepos(f);
        system.blockread(f,c,sizeof(c));
        if (c=#13) and not eof(f) then
          system.blockread(f,c,sizeof(c));
        if c<>#10 then
          system.seek(f,pos);
        if (c<>' ') and (c<>#10) and BreakOnSpacesOnly and
           (LastSpacePos>1) then
          begin
{$ifdef DEBUG}
            setlength(s,i); 
            filename:=strpas(@(filerec(f).Name));
            DebugMessage(filename,'s='+s,1,1);
{$endif DEBUG}
            i:=LastSpacePos;
{$ifdef DEBUG}
            setlength(s,i);
            DebugMessage(filename,'reduced to '+s,1,1);
{$endif DEBUG}
            system.seek(f,LastSpaceFilePos);
          end;
      end;

    if (c=#10) or eof(f) then
      linecomplete:=true;
    if (c=#10) then
      hasCR:=true;
    setlength(s,i);
  end;

function MemToStr(var B; Count: byte): string;
var S: string;
begin
  setlength(s,count);
  if Count>0 then Move(B,S[1],Count);
  MemToStr:=S;
end;

procedure StrToMem(S: string; var B);
begin
  if length(S)>0 then Move(S[1],B,length(S));
end;

function Max(A,B: longint): longint;
begin
  if A>B then Max:=A else Max:=B;
end;

function Min(A,B: longint): longint;
begin
  if A<B then Min:=A else Min:=B;
end;

function CharStr(const C: string; Count: integer): string;
{ UTF-8 port: C may be a multi-byte character; the result is capped at the
  255 bytes of a shortstring, on a character boundary. }
var I: integer;
begin
  CharStr:='';
  if (Count<=0) or (C='') then exit;
  for I:=1 to Count do
    begin
      if Length(CharStr)+Length(C)>255 then break;
      CharStr:=CharStr+C;
    end;
end;


function UpcaseStr(const S: string): string;
var
  I: Longint;
begin
  for I:=1 to length(S) do
    if S[I] in ['a'..'z'] then
      UpCaseStr[I]:=chr(ord(S[I])-32)
    else
      UpCaseStr[I]:=S[I];
  Setlength(UpcaseStr,length(s));
end;

function RExpand(const S: string; MinLen: byte): string;
begin
  if length(S)<MinLen then
    RExpand:=S+CharStr(' ',MinLen-length(S))
  else
    RExpand:=S;
end;

function LExpand(const S: string; MinLen: byte): string;
begin
  if length(S)<MinLen then
    LExpand:=CharStr(' ',MinLen-length(S))+S
  else
    LExpand:=S;
end;

function LTrim(const S: string): string;
var
  i : longint;
begin
  i:=1;
  while (i<length(s)) and (s[i]=' ') do
   inc(i);
  LTrim:=Copy(s,i,High(S));
end;

function RTrim(const S: string): string;
var
  i : longint;
begin
  i:=length(s);
  while (i>0) and (s[i]=' ') do
   dec(i);
  RTrim:=Copy(s,1,i);
end;

function Trim(const S: string): string;
var
  i,j : longint;
begin
  i:=1;
  while (i<length(s)) and (s[i]=' ') do
   inc(i);
  j:=length(s);
  while (j>0) and (s[j]=' ') do
   dec(j);
  Trim:=Copy(S,i,j-i+1);
end;

function IntToStr(L: longint): string;
var S: string;
begin
  Str(L,S);
  IntToStr:=S;
end;

function IntToStrL(L: longint; MinLen: sw_integer): string;
begin
  IntToStrL:=LExpand(IntToStr(L),MinLen);
end;

function IntToStrZ(L: longint; MinLen: sw_integer): string;
var S: string;
begin
  S:=IntToStr(L);
  if length(S)<MinLen then
    S:=CharStr('0',MinLen-length(S))+S;
  IntToStrZ:=S;
end;

function StrToInt(const S: string): longint;
var L: longint;
    C: integer;
begin
  Val(S,L,C); if C<>0 then L:=-1;
  LastStrToIntResult:=C;
  StrToInt:=L;
end;

function StrToCard(const S: string): cardinal;
var L: cardinal;
    C: integer;
begin
  Val(S,L,C); if C<>0 then L:=$ffffffff;
  LastStrToCardResult:=C;
  StrToCard:=L;
end;

function FloatToStr(D: Double; Decimals: byte): string;
var S: string;
    L: byte;
begin
  Str(D:0:Decimals,S);
  if length(S)>0 then
  while (S[1]=' ') do Delete(S,1,1);
  FloatToStr:=S;
end;

function FloatToStrL(D: Double; Decimals: byte; MinLen: byte): string;
begin
  FloatToStrL:=LExtendString(FloatToStr(D,Decimals),MinLen);
end;

function LExtendString(S: string; MinLen: byte): string;
begin
  LExtendString:=copy(SpaceStr,1,MinLen-length(S))+S;
end;

function GetStr(P: PString): string;
begin
  if P=nil then GetStr:='' else GetStr:=P^;
end;

procedure SetStr(var P: PString; const S: string);
begin
  if P <> nil then
    DisposeStr(PStr(P));
  if S = '' then
    P := nil
  else
    P := PString(NewStr(S));
end;

function GetPChar(P: PChar): string;
begin
  if P=nil then GetPChar:='' else GetPChar:=StrPas(P);
end;

procedure SplitPath(const S: string; var D: DirStr; var N: NameStr; var E: ExtStr);
var DA, NA, EA: AnsiString;
begin
  PathSplit(S,DA,NA,EA);
  D:=DA; N:=NA; E:=EA;
end;

function ExpandPath(const S: string): string;
begin
{$ifdef Unix}
  if (S='~') or (copy(S,1,2)='~'+PathSep) then
    ExpandPath:=PathExpand(PathJoin(GetEnv('HOME'),copy(S,3,High(S))))
  else
{$endif}
    ExpandPath:=PathExpand(S);
end;

function DirOf(const S: string): string;
begin
  DirOf:=PathAddSep(PathDir(S));
end;


function ExtOf(const S: string): string;
begin
  ExtOf:=PathExt(S);
end;


function NameOf(const S: string): string;
begin
  NameOf:=PathChangeExt(PathName(S),'');
end;

function NameAndExtOf(const S: string): string;
begin
  NameAndExtOf:=PathName(S);
end;

function DirAndNameOf(const S: string): string;
begin
  DirAndNameOf:=PathChangeExt(S,'');
end;

{ return Dos GetFTime value or -1 if the file does not exist }
function GetFileTime(const FileName: string): longint;
var T: longint;
    f: file;
    FM: integer;
begin
  if FileName='' then
    T:=-1
  else
    begin
      FM:=FileMode; FileMode:=0;
      EatIO; Dos.DosError:=0;
      Assign(f,FileName);
      {$I-}
      Reset(f);
      if InOutRes=0 then
        begin
          GetFTime(f,T);
          Close(f);
        end;
      {$I+}
      if (EatIO<>0) or (Dos.DosError<>0) then T:=-1;
      FileMode:=FM;
    end;
  GetFileTime:=T;
end;

function GetShortName(const n:string):string;
{$ifdef Windows}
var
  hs,hs2 : string;
  i : longint;
{$endif}
{$ifdef go32v2}
var
  hs : string;
{$endif}
begin
  GetShortName:=n;
{$ifdef Windows}
  hs:=n+#0;
  i:=Windows.GetShortPathName(@hs[1],@hs2[1],high(hs2));
  if (i>0) and (i<=high(hs2)) then
    begin
      setlength(hs2,strlen(@hs2[1]));
      GetShortName:=hs2;
    end;
{$endif}
{$ifdef go32v2}
  hs:=n;
  if Dos.GetShortName(hs) then
   GetShortName:=hs;
{$endif}
end;

function GetLongName(const n:string):string;
{$ifdef Windows}
var
  hs : string;
  hs2 : Array [0..255] of char;
  i : longint;
  j : pchar;
{$endif}
{$ifdef go32v2}
var
  hs : string;
{$endif}
begin
  GetLongName:=n;
{$ifdef Windows}
  hs:=n+#0;
  i:=Windows.GetFullPathNameA(@hs[1],256,hs2,j);
  if (i>0) and (i<=high(hs)) then
    begin
      hs:=strpas(hs2);
      GetLongName:=hs;
    end;
{$endif}
{$ifdef go32v2}
  hs:=n;
  if Dos.GetLongName(hs) then
   GetLongName:=hs;
{$endif}
end;


function EatIO: integer;
begin
  EatIO:=IOResult;
end;


function LowCase(C: char): char;
begin
  if ('A'<=C) and (C<='Z') then C:=chr(ord(C)+32);
  LowCase:=C;
end;


function LowcaseStr(S: string): string;
var I: Longint;
begin
  for I:=1 to length(S) do
      S[I]:=Lowcase(S[I]);
  LowcaseStr:=S;
end;


function BoolToStr(B: boolean; const TrueS, FalseS: string): string;
begin
  if B then BoolToStr:=TrueS else BoolToStr:=FalseS;
end;

function TUnstoredCollection.ReadItem(Ip: ipstream): Pointer;
begin
  Result := nil;
  raise EStreamableError.Create(pstream.StreamableError.peNotRegistered, StreamableName);
end;

procedure TUnstoredCollection.WriteItem(Item: Pointer; Os: opstream);
begin
  raise EStreamableError.Create(pstream.StreamableError.peNotRegistered, StreamableName);
end;

function TUnstoredSortedCollection.ReadItem(Ip: ipstream): Pointer;
begin
  Result := nil;
  raise EStreamableError.Create(pstream.StreamableError.peNotRegistered, StreamableName);
end;

procedure TUnstoredSortedCollection.WriteItem(Item: Pointer; Os: opstream);
begin
  raise EStreamableError.Create(pstream.StreamableError.peNotRegistered, StreamableName);
end;

procedure TNoDisposeCollection.FreeItem(Item: Pointer);
begin
  { don't do anything here }
end;

constructor TUnsortedStringCollection.CreateFrom(ALines: TUnsortedStringCollection);
begin
  if not Assigned(ALines) then
    Fail;
  inherited Create(ALines.Count, ALines.Count div 10);
  Assign(ALines);
end;

procedure TUnsortedStringCollection.Assign(ALines: TUnsortedStringCollection);
  procedure AddIt(P: Pointer);
  begin
    Insert(NewStr(GetStr(PString(P))));
  end;
begin
  FreeAll;
  if Assigned(ALines) then
    ALines.ForEach(@AddIt);
end;

procedure TUnsortedStringCollection.InsertStr(const S: string);
begin
  Insert(NewStr(S));
end;

function TUnsortedStringCollection.At(Index: Sw_Integer): PString;
begin
  At:=inherited At(Index);
end;

procedure TUnsortedStringCollection.FreeItem(Item: Pointer);
begin
  if Item<>nil then DisposeStr(Item);
end;

function TUnsortedStringCollection.ReadItem(Ip: ipstream): Pointer;
begin
  Result := Ip.ReadString;
end;

procedure TUnsortedStringCollection.WriteItem(Item: Pointer; Os: opstream);
begin
  Os.WriteString(PStr(Item));
end;

class function TUnsortedStringCollection.Build: TStreamable;
begin
  Result := TUnsortedStringCollection.Create(streamableInit);
end;

function TUnsortedStringCollection.StreamableName: ShortString;
begin
  Result := 'wutils.TUnsortedStringCollection';
end;

function TIntCollection.Contains(Item: ptrint): boolean;
var Index: sw_integer;
begin
  Contains:=Search(pointer(Item),Index);
end;

function TIntCollection.AtInt(Index: sw_integer): ptrint;
begin
  AtInt:=PtrInt(At(Index));
end;

procedure TIntCollection.Add(Item: ptrint);
begin
  Insert(pointer(Item));
end;

function TIntCollection.Compare(Key1, Key2: Pointer): sw_Integer;
var K1: PtrInt absolute Key1;
    K2: PtrInt absolute Key2;
    R: integer;
begin
  if K1<K2 then R:=-1 else
  if K1>K2 then R:= 1 else
  R:=0;
  Compare:=R;
end;

procedure TIntCollection.FreeItem(Item: Pointer);
begin
  { do nothing here }
end;

constructor TNulStream.Create;
begin
  inherited Create;
  Position := 0;
end;

function TNulStream.GetPos: Int64;
begin
  GetPos := Position;
end;

function TNulStream.GetSize: Int64;
begin
  GetSize := Position;
end;

procedure TNulStream.Read(var Buf; Count: Longint);
begin
  Error(stReadError, 0);
end;

procedure TNulStream.Seek(Pos: Int64);
begin
  if Pos <= Position then
    Position := Pos;
end;

procedure TNulStream.Write(const Buf; Count: Longint);
begin
  Inc(Position, Count);
end;

constructor TSubStream.Create(AStream: TStream; AStartPos, ASize: Int64);
begin
  inherited Create;
  if not Assigned(AStream) then
    Fail;
  S := AStream;
  StartPos := AStartPos;
  StreamSize := ASize;
  Seek(0);
end;

function TSubStream.GetPos: Int64;
begin
  GetPos := S.GetPos - StartPos;
end;

function TSubStream.GetSize: Int64;
begin
  GetSize := StreamSize;
end;

procedure TSubStream.Read(var Buf; Count: Longint);
var
  Pos, RCount: Int64;
begin
  Pos := GetPos;
  if Pos + Count > StreamSize then
    RCount := StreamSize - Pos
  else
    RCount := Count;
  S.Read(Buf, Longint(RCount));
  if RCount < Count then
    Error(stReadError, 0);
end;

procedure TSubStream.Seek(Pos: Int64);
var
  RPos: Int64;
begin
  if Pos <= StreamSize then
    RPos := Pos
  else
    RPos := StreamSize;
  S.Seek(StartPos + RPos);
end;

procedure TSubStream.Write(const Buf; Count: Longint);
begin
  S.Write(Buf, Count);
end;

constructor TFastBufStream.Create(const FileName: FNameStr; Mode: Word; Size: Longint);
begin
  inherited Create(FileName, Mode, Size);
  BasePos := 0;
end;

procedure TFastBufStream.Seek(Pos: Int64);
var
  RelOfs: Int64;
begin
  RelOfs := Pos - BasePos;
  if (RelOfs < 0) or (RelOfs >= BufLen) or (BufLen = 0) then
  begin
    inherited Seek(Pos);
    BasePos := Pos - BufPos;
  end
  else
  begin
    BufPos := Longint(RelOfs);
    Position := Pos;
  end;
end;

procedure TFastBufStream.Readline(var s:string;var linecomplete,hasCR : boolean);
  var
    c : char;
    i,pos,StartPos,j,need : longint;
    lead : byte;
    charsInS : boolean;
  begin
    linecomplete:=false;
    c:=#0;
    i:=0;
    { this created problems for lines longer than 255 characters
      now those lines are cutted into pieces without warning PM }
    { changed implicit 255 to High(S), so it will be automatically extended
      when longstrings eventually become default - Gabor }
    if (BufLen - BufPos >= High(S)) and (GetPos + High(S) < GetSize) then
      begin
        StartPos:=GetPos;
        //read(S[1],High(S));
        System.Move(Buffer[BufPos], S[1], High(S));
        charsInS:=true;
      end
    else
      CharsInS:=false;

    while (CharsInS or not (GetPos >= GetSize)) and
          (c<>#10) and (i<High(S)) do
     begin
       if CharsInS then
         c:=s[i+1]
       else
         Read(c, SizeOf(c));
       if c<>#10 then
        begin
          inc(i);
          if not CharsInS then
            s[i]:=c;
        end;
     end;
    if CharsInS then
      begin
        if c=#10 then
          Seek(StartPos+i+1)
        else
          Seek(StartPos+i);
      end;
    { if there was a CR LF then remove the CR Dos newline style }
    if (i>0) and (s[i]=#13) then
      begin
        dec(i);
      end;
    if (c=#13) and (not (GetPos >= GetSize)) then
      begin
        Read(c, SizeOf(c));
      end;
    if (i=High(S)) and not (GetPos >= GetSize) then
      begin
        pos:=GetPos;
        Read(c, SizeOf(c));
        if (c=#13) and not (GetPos >= GetSize) then
          Read(c, SizeOf(c));
        if c<>#10 then
          Seek(pos);
      end;
    if (c=#10) or (GetPos >= GetSize) then
      linecomplete:=true;
    if (c=#10) then
      hasCR:=true; 
    { the end of the line buffer must not cut a UTF-8 character in two: the character goes to the next piece }
    if Utf8Enabled and (not linecomplete) and (i=High(S)) then
      begin
        j:=i;
        while (j>1) and (i-j<3) and ((Byte(s[j]) and $C0)=$80) do
          dec(j);
        lead:=Byte(s[j]);
        if (lead>=$C2) and (lead<=$DF) then need:=2
        else if (lead>=$E0) and (lead<=$EF) then need:=3
        else if (lead>=$F0) and (lead<=$F4) then need:=4
        else need:=1;
        if (need>1) and (j+need-1>i) then
          begin
            Seek(GetPos-(i-j+1));
            i:=j-1;
          end;
      end;
    SetLength(s,i);    
  end;



function TTextCollection.Compare(Key1, Key2: Pointer): Sw_Integer;
var K1: PString absolute Key1;
    K2: PString absolute Key2;
    R: Sw_integer;
    S1,S2: string;
begin
  S1:=UpCaseStr(K1^);
  S2:=UpCaseStr(K2^);
  if S1<S2 then R:=-1 else
  if S1>S2 then R:=1 else
  R:=0;
  Compare:=R;
end;

function TTextCollection.LookUp(const S: string; var Idx: sw_integer): string;
var OLI,ORI,Left,Right,Mid: integer;
    {LeftP,RightP,}MidP: PString;
    {LeftS,}MidS{,RightS}: string;
    FoundS: string;
    UpS : string;
begin
  Idx:=-1; FoundS:='';
  Left:=0; Right:=Count-1;
  UpS:=UpCaseStr(S);
  while Left<=Right do
    begin
      OLI:=Left; ORI:=Right;
      Mid:=Left+(Right-Left) div 2;
      MidP:=At(Mid);
      MidS:=UpCaseStr(MidP^);
      if copy(MidS,1,length(UpS))=UpS then
        begin
          Idx:=Mid; FoundS:=GetStr(MidP);
          { exit immediately if exact match PM }
          If Length(MidS)=Length(UpS) then
            break;
        end;
      if UpS<MidS then
        Right:=Mid
      else
        Left:=Mid;
      if (OLI=Left) and (ORI=Right) then
        begin
          if (Left<Right) then
            Left:=Right
          else
            Break;
        end;
    end;
  LookUp:=FoundS;
end;

function TrimEndSlash(const Path: string): string;
begin
  TrimEndSlash:=PathDelSep(Path);
end;

function CompareText(S1, S2: string): integer;
var R: integer;
begin
  S1:=UpcaseStr(S1); S2:=UpcaseStr(S2);
  if S1<S2 then R:=-1 else
  if S1>S2 then R:= 1 else
  R:=0;
  CompareText:=R;
end;

function FormatPath(Path: string): string;
begin
  FormatPath:=PathNative(Path);
end;

{ InComplete taken from the directory of the file Base }
function CompletePath(const Base, InComplete: string): string;
begin
  CompletePath:=PathExpandFrom(PathNative(InComplete),PathDir(PathNative(Base)));
end;

function CompleteURL(const Base, URLRef: string): string;
var P: integer;
    Drive: string[20];
    IsComplete: boolean;
    S: string;
    Ref: string;
    Bookmark: string;
begin
  IsComplete:=false; Ref:=URLRef;
  P:=Pos(':',Ref);
  if P=0 then Drive:='' else Drive:=UpcaseStr(copy(Ref,1,P-1));
  if Drive<>'' then
  if (Drive='MAILTO') or (Drive='FTP') or (Drive='HTTP') or
     (Drive='GOPHER') or (Drive='FILE') then
    IsComplete:=true;
  if IsComplete then S:=Ref else
  begin
    P:=Pos('#',Ref);
    if P=0 then
      Bookmark:=''
    else
      begin
        Bookmark:=copy(Ref,P+1,length(Ref));
        Ref:=copy(Ref,1,P-1);
      end;
    S:=CompletePath(Base,Ref);
    if Bookmark<>'' then
      S:=S+'#'+Bookmark;
  end;
  CompleteURL:=S;
end;

function OptimizePath(Path: string; MaxLen: integer): string;
var i                : integer;
    BackSlashs       : array[1..20] of integer;
    BSCount          : integer;
    Jobbra           : boolean;
    Jobb, Bal        : byte;
    Hiba             : boolean;
begin
 if length(Path)>MaxLen then
 begin
  BSCount:=0; Jobbra:=true;
  for i:=1 to length(Path) do if Path[i]=DirSep then
      begin
        Inc(BSCount);
        BackSlashs[BSCount]:=i;
      end;
  i:=BSCount div 2;
  Hiba:=false;
  Bal:=i; Jobb:=i+1;
  case i of 0  : ;
            1  : Path:=copy(Path, 1, BackSlashs[1])+'..'+
                       copy(Path, BackSlashs[2], length(Path));
            else begin
                   while (BackSlashs[Bal]+(length(Path)-BackSlashs[Jobb]) >=
                          MaxLen) and not Hiba do
                         begin
                           if Jobbra then begin
                                           if Jobb<BSCount then inc(Jobb)
                                                           else Hiba:=true;
                                           Jobbra:=false;
                                          end
                                     else begin
                                           if Bal>1 then dec(Bal)
                                                    else Hiba:=true;
                                           Jobbra:=true;
                                          end;
                         end;
                   Path:=copy(Path, 1, BackSlashs[Bal])+'..'+
                         copy(Path, BackSlashs[Jobb], length(Path));
                 end;
  end;
 end;
  if length(Path)>MaxLen then
  begin
    i:=Pos('\..\',Path);
    if i>0 then Path:=copy(Path,1,i-1)+'..'+copy(Path,i+length('\..\'),length(Path));
  end;
 OptimizePath:=Path;
end;

function Now: longint;
var D: DateTime;
    W: word;
    L: longint;
begin
  FillChar(D,sizeof(D),0);
  GetDate(D.Year,D.Month,D.Day,W);
  GetTime(D.Hour,D.Min,D.Sec,W);
  PackTime(D,L);
  Now:=L;
end;

function FormatDateTimeL(L: longint; const Format: string): string;
var D: DateTime;
begin
  UnpackTime(L,D);
  FormatDateTimeL:=FormatDateTime(D,Format);
end;

function FormatDateTime(const D: DateTime; const Format: string): string;
var I: sw_integer;
    CurCharStart: sw_integer;
    CurChar: char;
    CurCharCount: integer;
    DateS: string;
    C: char;
procedure FlushChars;
var S: string;
    I: sw_integer;
begin
  S:='';
  for I:=1 to CurCharCount do
    S:=S+CurChar;
  case CurChar of
    'y' : S:=IntToStrL(D.Year,length(S));
    'm' : S:=IntToStrZ(D.Month,length(S));
    'd' : S:=IntToStrZ(D.Day,length(S));
    'h' : S:=IntToStrZ(D.Hour,length(S));
    'n' : S:=IntToStrZ(D.Min,length(S));
    's' : S:=IntToStrZ(D.Sec,length(S));
  end;
  DateS:=DateS+S;
end;
begin
  DateS:='';
  CurCharStart:=-1; CurCharCount:=0; CurChar:=#0;
  for I:=1 to length(Format) do
  begin
    C:=Format[I];
    if (C<>CurChar) or (CurCharStart=-1) then
      begin
        if CurCharStart<>-1 then FlushChars;
        CurCharCount:=1; CurCharStart:=I;
      end
    else
      Inc(CurCharCount);
    CurChar:=C;
  end;
  FlushChars;
  FormatDateTime:=DateS;
end;

function DeleteFile(const FileName: string): integer;
var f: file;
begin
{$I-}
  Assign(f,FileName);
  Erase(f);
  DeleteFile:=EatIO;
{$I+}
end;

function ExistsFile(const FileName: string): boolean;
var
  Dir : SearchRec;
begin
  Dos.FindFirst(FileName,Archive+ReadOnly,Dir);
  ExistsFile:=(Dos.DosError=0);
  Dos.FindClose(Dir);
end;

{ returns zero for empty and non existant files }

function SizeOfFile(const FileName: string): longint;
var
  Dir : SearchRec;
begin
  Dos.FindFirst(FileName,Archive+ReadOnly,Dir);
  if (Dos.DosError=0) then
    SizeOfFile:=Dir.Size
  else
    SizeOfFile:=0;
  Dos.FindClose(Dir);
end;

function ExistsDir(const DirName: string): boolean;
var
  Dir : SearchRec;
begin
  Dos.FindFirst(TrimEndSlash(DirName),anyfile,Dir);
  { if a file is found it is also reported
    at least for some Dos version
    so we need to check the attributes PM }
  ExistsDir:=(Dos.DosError=0) and ((Dir.attr and Directory) <> 0);
  Dos.FindClose(Dir);
end;

function CompleteDir(const Path: string): string;
begin
  { a bare drive "c:" stays as it is }
  CompleteDir:=PathAddSep(Path);
end;

function GetCurDir: string;
var S: string;
begin
  GetDir(0,S);
  GetCurDir:=PathAddSep(S);
end;

function GenTempFileName: string;
var Dir: string;
    Name: string;
    I: integer;
    OK: boolean;
    Path: string;
begin
  Dir:=GetEnv('TEMP');
  if Dir='' then Dir:=GetEnv('TMP');
{$ifdef HASAMIGA}
  if Dir='' then Dir:='T:';
{$endif}
{$ifdef Unix}
  if Dir='' then Dir:=GetEnv('TMPDIR');
  if Dir='' then Dir:='/tmp';
{$endif}
  if (Dir<>'') then if not ExistsDir(Dir) then Dir:='';
  if Dir='' then Dir:=GetCurDir;
  repeat
    Name:=TempFirstChar;
    for I:=2 to TempNameLen do
      Name:=Name+chr(ord('a')+random(ord('z')-ord('a')+1));
    Name:=Name+TempExt;
    Path:=CompleteDir(Dir)+Name;
    OK:=not ExistsFile(Path);
  until OK;
  GenTempFileName:=Path;
end;

function CopyFile(const SrcFileName, DestFileName: string): boolean;
var
  SrcF, DestF: TBufStream;
  OK: boolean;
begin
  SrcF := nil;
  DestF := nil;
  SrcF := TBufStream.Create(SrcFileName, stOpenRead, 4096);
  OK := Assigned(SrcF) and (SrcF.Status = stOk);
  if OK then
  begin
    DestF := TBufStream.Create(DestFileName, stCreate, 1024);
    OK := Assigned(DestF) and (DestF.Status = stOk);
  end;
  if OK then
    DestF.CopyFrom(SrcF, SrcF.GetSize);
  DestF.Free;
  SrcF.Free;
  CopyFile := OK;
end;

procedure RegisterWUtils;
begin
{$ifndef NOOBJREG}
  TStreamableClass.Create('wutils.TUnsortedStringCollection', @TUnsortedStringCollection.Build);
{$endif}
end;

Procedure DebugMessage(AFileName, AText : string; ALine, APos : sw_word); // calls DebugMessage
begin
  DebugMessageS(Afilename,AText,'','',aline,apos);
end;

Procedure WUtilsDebugMessage(AFileName, AText : string; ALine, APos : string;nrLine, nrPos : sw_word);
begin
  writeln(stderr,AFileName,' (',ALine,',',APos,') ',AText);
  flush(stderr);
end;

BEGIN
  Randomize;
END.
