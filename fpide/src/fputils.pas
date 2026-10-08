{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    Utilility routines used by the IDE

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit FPUtils;
{$modeswitch nestedprocvars}{$modeswitch autoderef}

interface

uses
  Sysutils,
  Objects,TvPath;

const
  dirsep = PathSep;

{$ifdef Unix}
  listsep = [';',':'];
  exeext = '';
  pasext = '.pas';
  ppext  = '.pp';
{$else}
  {$ifdef HASAMIGA}
    listsep = [';'];
    exeext = '';
    pasext = '.pas';
    ppext  = '.pp';
  {$else HASAMIGA}
  listsep = [';'];
  exeext = '.exe';
  pasext = '.pas';
  ppext  = '.pp';
  {$endif HASAMIGA}
{$endif}


function SmartPath(Path: string): string;
Function FixPath(s:string;allowdot:boolean):string;
function FixFileName(const s:string):string;
function MakeExeName(const fn:string):string;
function Center(const S: string; Len: byte): string;
function FitStr(const S: string; Len: byte): string;
{ tv3 port: FV's directory picker was not carried over; a one-line input box asks for the path. }
procedure SelectDir(var S: string; HistoryID: word);
{ Debug aid: appends a line to the file named by $FP_DEBUG_LOG (tv3 owns stderr and the screen, so writeln is no use). }
procedure DbgLog(const S: string);
function LowercaseStr(const S: string): string;
{function DirOf(const S: string): string;
function ExtOf(const S: string): string;
function NameOf(const S: string): string;
function NameAndExtOf(const S: string): string;}
function StrToExtended(S: string): Extended;
function Power(const A,B: double): double;
function MatchesMask(What, Mask: string): boolean;
function MatchesMaskList(What, MaskList: string): boolean;
function MatchesFileList(What, FileList: string): boolean;
function EatIO: integer;
function RenameFile(const OldFileName,NewFileName: string): boolean;
function LocateFile(FileList: string): string;
function LocatePasFile(const FileName:string):string;
function LocateExeFile(var FileName:string): boolean;
function EraseFile(FileName: string): boolean;
function GetStr(const P: PString): string;
procedure ReplaceStr(var S: string; const What,NewS: string);
procedure ReplaceStrI(var S: string; What: string; const NewS: string);

const ListSeparator      : char = ';';

implementation

uses Dos,
     Views,Dialogs,
     WUtils,TvWild,
     FPVars,FPSwitch;

procedure DbgLog(const S: string);
var F: Text;
    N: string;
begin
  N:=GetEnvironmentVariable('FP_DEBUG_LOG');
  if N='' then Exit;
  Assign(F,N);
  {$I-}
  Append(F);
  if IOResult<>0 then Rewrite(F);
  {$I+}
  if IOResult<>0 then Exit;
  writeln(F,S);
  Close(F);
end;

procedure SelectDir(var S: string; HistoryID: word);
var T: ShortString;
begin
  T:=S;
  if InputBox('Directory','~D~irectory',T,255)=cmOK then
    S:=T;
end;

function IntToStr(L: longint): string;
var S: string;
begin
  Str(L,S);
  IntToStr:=S;
end;

function IntToStrZ(L: longint; MinLen: byte): string;
var S: string;
begin
  S:=IntToStr(L);
  if length(S)<MinLen then S:=CharStr('0',MinLen-length(S))+S;
  IntToStrZ:=S;
end;

function IntToStrL(L: longint; MinLen: byte): string;
var S: string;
begin
  S:=IntToStr(L);
  if length(S)<MinLen then S:=CharStr(' ',MinLen-length(S))+S;
  IntToStrL:=S;
end;

function SmartPath(Path: string): string;
var S: string;
begin
  S:=GetCurDir;
  if PathSameName(copy(Path,1,length(S)),S) then
     system.Delete(Path,1,length(S));
  SmartPath:=Path;
end;


Function FixPath(s:string;allowdot:boolean):string;
begin
  { a bare drive ("c:") gets no separator }
  s:=PathAddSep(PathNative(s));
  if (not allowdot) and (s='.'+DirSep) then
   s:='';
  FixPath:=s;
end;


function FixFileName(const s:string):string;
{$ifdef Unix}
begin
  { A Unix name is kept as it is: the file system tells Foo from foo and a backslash is a letter of a name. }
  FixFileName:=s;
end;
{$else}
begin
  FixFileName:=LowerCaseStr(PathNative(s));
end;
{$endif}


function MakeExeName(const fn:string):string;
begin
  MakeExeName:=PathChangeExt(fn,ExeExt);
end;


function Center(const S: string; Len: byte): string;
begin
  Center:=LExpand(S+CharStr(' ',Max(0,(Len-length(S)) div 2)),Len);
end;

function FitStr(const S: string; Len: byte): string;
begin
  FitStr:=RExpand(copy(S,1,Len),Len);
end;


function LowerCaseStr(const S: string): string;
var
  I: Longint;
begin
  for I:=1 to length(S) do
    if S[I] in ['A'..'Z'] then
      LowerCaseStr[I]:=chr(ord(S[I])+32)
    else
      LowerCaseStr[I]:=S[I];
  LowercaseStr[0]:=S[0];
end;

{function DirOf(const S: string): string;
var D: DirStr; E: ExtStr; N: NameStr;
begin
  SplitPath(S,D,N,E);
  if (D<>'') and (D[Length(D)]<>DirSep) then
   DirOf:=D+DirSep
  else
   DirOf:=D;
end;


function ExtOf(const S: string): string;
var D: DirStr; E: ExtStr; N: NameStr;
begin
  SplitPath(S,D,N,E);
  ExtOf:=E;
end;


function NameOf(const S: string): string;
var D: DirStr; E: ExtStr; N: NameStr;
begin
  SplitPath(S,D,N,E);
  NameOf:=N;
end;

function NameAndExtOf(const S: string): string;
var D: DirStr; E: ExtStr; N: NameStr;
begin
  SplitPath(S,D,N,E);
  NameAndExtOf:=N+E;
end; }

function StrToExtended(S: string): Extended;
var R : Extended;
    C : integer;
begin
  Val(S,R,C);
  StrToExtended:=R;
end;

function Power(const A,B: double): double;
begin
  if A=0 then Power:=0
         else Power:=exp(B*ln(A));
end;

function MatchesMask(What, Mask: string): boolean;
begin
  MatchesMask:=WildMatch(What,Mask);
end;

function MatchesMaskList(What, MaskList: string): boolean;
begin
  MatchesMaskList:=(What<>'') and WildMatchList(What,MaskList);
end;

function MatchesFileList(What, FileList: string): boolean;
var P: integer;
    Match: boolean;
    WD,FD : record D: DirStr; N: NameStr; E: ExtStr; end;
    F: string;
begin
  Match:=false;
  SplitPath(What,WD.D,WD.N,WD.E);
  if What<>'' then
  repeat
    P:=Pos(ListSeparator, FileList);
    if P=0 then P:=length(FileList)+1;
    F:=copy(FileList,1,P-1);
    SplitPath(F,FD.D,FD.N,FD.E);
    Match:=MatchesMask(WD.D+WD.N,FD.D+FD.N) and
           MatchesMask(WD.E,FD.E);
    Delete(FileList,1,P);
  until Match or (FileList='');
  MatchesFileList:=Match;
end;

function EatIO: integer;
begin
  EatIO:=IOResult;
end;

function RenameFile(const OldFileName,NewFileName: string): boolean;
var f: file;
begin
  Assign(f,OldFileName);
  Rename(f,NewFileName);
  RenameFile:=(EatIO=0);
end;

function LocateFile(FileList: string): string;
var FilePath: string;
function CheckFile(Path,Name: string): boolean;
var OK: boolean;
begin
  Path:=CompleteDir(Path);
  Path:=Path+Name;
  OK:=ExistsFile(Path);
  if OK then FilePath:=Path;
  CheckFile:=OK;
end;
function LocateSingleFile(FileName: string): boolean;
var OK: boolean;
begin
  OK:=CheckFile(ExpandPath('.'),FileName);
  if OK=false then OK:=CheckFile(StartupDir,FileName);
  if OK=false then OK:=CheckFile(IDEDir,FileName);
  LocateSingleFile:=OK;
end;
var P: integer;
begin
  FilePath:='';
  if FileList<>'' then
  repeat
    P:=Pos(ListSeparator,FileList); if P=0 then P:=length(FileList)+1;
    LocateSingleFile(copy(FileList,1,P-1));
    Delete(FileList,1,P);
  until (FilePath<>'') or (FileList='');
  LocateFile:=FilePath;
end;

function LocatePasFile(const FileName:string):string;
var
  s : string;
begin
  LocatePasFile:=FileName;
  if ExistsFile(FileName) or (ExtOf(FileName)<>'') then
   exit;
  S:=FileName+PPExt;
  if ExistsFile(S) then
   begin
     LocatePasFile:=S;
     exit;
   end;
  S:=FileName+PasExt;
  if ExistsFile(S) then
   begin
     LocatePasFile:=S;
     exit;
   end;
end;

function LocateExeFile(var FileName:string): boolean;
var
  dir : string;
  s : ansistring;
  i : longint;
begin
  LocateExeFile:=False;
  if ExistsFile(FileName) then
    begin
      LocateExeFile:=true;
      Exit;
    end;

  S:=sysutils.GetEnvironmentVariable('PATH');
  While Length(S)>0 do
    begin
      i:=1;
      While (i<=Length(S)) and not (S[i] in ListSep) do
        Inc(i);
      Dir:=CompleteDir(Copy(S,1,i-1));
      if i<Length(S) then
        Delete(S,1,i)
      else
        S:='';
      if ExistsFile(Dir+FileName) then
        Begin
           FileName:=Dir+FileName;
           LocateExeFile:=true;
           Exit;
        End;
   end;
end;

function GetStr(const P: PString): string;
begin
  if P=nil then GetStr:='' else GetStr:=P^;
end;

function EraseFile(FileName: string): boolean;
var f: file;
begin
  if FileName='' then Exit;
  {$I-}
  Assign(f,FileName);
  Erase(f);
  {$I+}
  EraseFile:=(EatIO=0);
end;

procedure ReplaceStr(var S: string; const What,NewS: string);
var I : Sw_integer;
begin
  repeat
    I:=Pos(What,S);
    if I>0 then
    begin
      Delete(S,I,length(What));
      Insert(NewS,S,I);
    end;
  until I=0;
end;

procedure ReplaceStrI(var S: string; What: string; const NewS: string);
var I : integer;
    UpcaseS: string;
begin
  UpcaseS:=UpcaseStr(S); What:=UpcaseStr(What);
  repeat
    I:=Pos(What,UpcaseS);
    if I>0 then
    begin
      Delete(S,I,length(What));
      Insert(NewS,S,I);
      Delete(UpcaseS,I,length(What));
      Insert(NewS,UpcaseS,I);
    end;
  until I=0;
end;


END.
