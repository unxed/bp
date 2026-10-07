{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    Misc routines for the IDE

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$i globdir.inc}

unit FPIntf;
{$modeswitch nestedprocvars}{$modeswitch autoderef}

{$mode objfpc}{$modeswitch nestedprocvars}{$modeswitch autoderef}

interface

{ Run }
function  GetRunParameters: string;
procedure SetRunParameters(const Params: string);
function GetRunDir: string;
procedure SetRunDir(const Params: string);

{ Compile }
procedure Compile(const FileName, ConfigFile: string);
procedure SetPrimaryFile(const fn:string);
function LinkAfter : boolean;
{ the compiler to use: CompilerSetting is 'auto', 'builtin' or the path of an external compiler (env FP_COMPILER wins) }
procedure ResolveCompiler;
function  CompilerDescription: string;


implementation

uses
{$ifdef EMBED_COMPILER}
  Compiler,
{$endif}
  Comphook,
  sysutils,Process,Version,FPExtComp,TvProc,App,Views,Drivers,WEditor,FPConst,FPViews,
{$ifndef NODEBUG}
  FPDebug,
{$endif NODEBUG}
  FPRedir,FPVars,FpCompil,
  FPUtils,FPSwitch,WUtils;

{****************************************************************************
                                   Run
****************************************************************************}

var
  RunDir,
  RunParameters : string;

function LinkAfter : boolean;
begin
  LinkAfter:=LinkAfterSwitches.GetBooleanItem(0);
end;

function GetRunParameters: string;
begin
  GetRunParameters:=RunParameters;
end;

procedure SetRunParameters(const Params: string);
begin
  RunParameters:=Params;
{$ifndef NODEBUG}
  If assigned(Debugger) then
    Debugger.SetArgs(RunParameters);
{$endif}
end;

function GetRunDir: string;
begin
  GetRunDir:=RunDir;
end;

procedure SetRunDir(const Params: string);
begin
  RunDir:=Params;
{$ifndef NODEBUG}
  If assigned(Debugger) then
    Debugger.SetDir(RunDir);
{$endif}
end;


{****************************************************************************
                                   Compile
****************************************************************************}

var
  CatchErrorLongJumpBuffer : jmp_buf;

procedure CatchCompilationErrors;
begin
  LongJmp(CatchErrorLongJumpBuffer,1);
end;

const
  { what 'auto' looks for on the PATH }
  DefaultExternalCompiler = 'fpc';

procedure ResolveCompiler;
var
  S,Exe: string;
begin
  S:=GetEnvironmentVariable('FP_COMPILER');
  if S='' then
    S:=CompilerSetting;
  if (S='') or (LowerCase(S)='auto') then
    begin
      Exe:=DefaultExternalCompiler;
      UseExternalCompiler:=LocateExeFile(Exe);
      if UseExternalCompiler then
        ExternalCompilerExe:=Exe
{$ifndef EMBED_COMPILER}
      else
        begin
          ExternalCompilerExe:=DefaultExternalCompiler;
          UseExternalCompiler:=true;
        end
{$endif}
      ;
    end
  else if (LowerCase(S)='builtin') or (LowerCase(S)='built-in') then
    begin
{$ifdef EMBED_COMPILER}
      UseExternalCompiler:=false;
{$else}
      { no built-in compiler in this build: use the one of the system }
      Exe:=DefaultExternalCompiler;
      LocateExeFile(Exe);
      ExternalCompilerExe:=Exe;
      UseExternalCompiler:=true;
{$endif}
    end
  else
    begin
      Exe:=S;
      UseExternalCompiler:=LocateExeFile(Exe);
      if UseExternalCompiler then
        ExternalCompilerExe:=Exe
      else
        ExternalCompilerExe:=S;
      { a path that does not exist is kept: Compile says so }
      UseExternalCompiler:=true;
    end;
end;

function CompilerDescription: string;
begin
  if UseExternalCompiler then
    CompilerDescription:=ExternalCompilerExe+' '+RunFirstLine(ExternalCompilerExe,['-iV'])
  else
    CompilerDescription:='built-in '+Version.version_string;
end;

{ the message of one line of the output of an external compiler:
    file.pas(12,5) Error: text      file.pas(12) Warning: text      Fatal: text      Compiling file.pas }
procedure ExternalCompilerLine(const Line: AnsiString);
var
  L,Module,Text: AnsiString;
  P,P1,P2,LineNb,ColNb,Err: LongInt;
  Level: LongInt;
  function Severity(const T: AnsiString; var Rest: AnsiString): LongInt;
  begin
    Severity:=0;
    if Pos('Fatal: ',T)=1 then Severity:=V_Fatal
    else if Pos('Error: ',T)=1 then Severity:=V_Error
    else if Pos('Warning: ',T)=1 then Severity:=V_Warning
    else if Pos('Note: ',T)=1 then Severity:=V_Note
    else if Pos('Hint: ',T)=1 then Severity:=V_Hint
    else if Pos('Info: ',T)=1 then Severity:=V_Info;
    if Severity<>0 then
      Rest:=Copy(T,Pos(' ',T)+1,Length(T));
  end;
begin
  L:=Line;
  while (L<>'') and (L[Length(L)] in [#13,#10]) do
    Delete(L,Length(L),1);
  if L='' then Exit;
  if Pos('Compiling ',L)=1 then
    begin
      status.currentsource:=Copy(L,11,Length(L));
      Exit;
    end;
  P1:=Pos(' lines compiled',L);
  if P1>0 then
    begin
      Val(Copy(L,1,P1-1),status.compiledlines,Err);
      Exit;
    end;
  { file(line[,col]) Severity: text }
  P:=Pos('(',L);
  if P>1 then
    begin
      P2:=Pos(') ',L);
      if P2>P then
        begin
          Module:=Copy(L,1,P-1);
          Text:=Copy(L,P+1,P2-P-1);
          P1:=Pos(',',Text);
          Err:=0;
          if P1>0 then
            begin
              Val(Copy(Text,1,P1-1),LineNb,Err);
              if Err=0 then
                Val(Copy(Text,P1+1,Length(Text)),ColNb,Err);
            end
          else
            begin
              Val(Text,LineNb,Err);
              ColNb:=0;
            end;
          if Err=0 then
            begin
              Level:=Severity(Copy(L,P2+2,Length(L)),Text);
              if Level<>0 then
                begin
                  if Level in [V_Fatal,V_Error] then
                    Inc(status.errorCount);
                  CompilerMessageWindow.AddMessage(Level or V_LineInfo,Text,Module,LineNb,ColNb);
                  Exit;
                end;
            end;
        end;
    end;
  { a message without a position (the summary of the compiler, the linker) is shown, not counted: the exit
    code of the compiler decides if there was an error when no message with a position said so }
  Level:=Severity(L,Text);
  if Level<>0 then
    CompilerMessageWindow.AddMessage(Level,Text,'',0,0);
end;

{ an external compiler reads the files, not the editors: write the modified ones that have a name }
procedure SaveModifiedSources;
  procedure DoSave(P: PView);
  begin
    if P.HelpCtx=hcSourceWindow then
      if PSourceWindow(P).Editor.GetModified and (PSourceWindow(P).Editor.FileName<>'') then
        Message(P,evCommand,cmSave,nil);
  end;
begin
  Desktop.ForEach(@DoSave);
end;

{ program, unit or library: the first word of the source that is not in a comment }
function SourceKind(const FileName: string): string;
var
  F: TextFile;
  S,W: AnsiString;
  InBrace,InParen: boolean;
  I: LongInt;
  Lines: LongInt;
begin
  Result:='program';
  AssignFile(F,FileName);
  {$I-}
  Reset(F);
  {$I+}
  if IOResult<>0 then Exit;
  InBrace:=false; InParen:=false; Lines:=0;
  while not EOF(F) and (Lines<200) do
    begin
      ReadLn(F,S);
      Inc(Lines);
      I:=1;
      while I<=Length(S) do
        begin
          if InBrace then begin if S[I]='}' then InBrace:=false; Inc(I); end
          else if InParen then
            begin
              if (S[I]='*') and (I<Length(S)) and (S[I+1]=')') then begin InParen:=false; Inc(I); end;
              Inc(I);
            end
          else if S[I]='{' then begin InBrace:=true; Inc(I); end
          else if (S[I]='(') and (I<Length(S)) and (S[I+1]='*') then begin InParen:=true; Inc(I,2); end
          else if (S[I]='/') and (I<Length(S)) and (S[I+1]='/') then I:=Length(S)+1
          else if S[I] in ['A'..'Z','a'..'z','_'] then
            begin
              W:='';
              while (I<=Length(S)) and (S[I] in ['A'..'Z','a'..'z','_','0'..'9']) do
                begin W:=W+LowerCase(S[I]); Inc(I); end;
              if (W='unit') or (W='library') or (W='program') then
                begin
                  Result:=W;
                  CloseFile(F);
                  Exit;
                end;
              { a source without the program heading is a program }
              CloseFile(F);
              Exit;
            end
          else
            Inc(I);
        end;
    end;
  CloseFile(F);
end;

procedure CompileExternal(const FileName, ConfigFile: string);
var
  P: TProcess;
  Exe: string;
  CmdLine: AnsiString;
  Buf: array[0..4095] of char;
  Pending: AnsiString;
  N,NL: LongInt;
  Aborted: boolean;
  Kind: string;
  procedure Feed(const Data: AnsiString);
  begin
    Pending:=Pending+Data;
    NL:=Pos(#10,Pending);
    while NL>0 do
      begin
        ExternalCompilerLine(Copy(Pending,1,NL-1));
        Delete(Pending,1,NL);
        NL:=Pos(#10,Pending);
      end;
  end;
begin
  SaveModifiedSources;
  Exe:=ExternalCompilerExe;
  if not LocateExeFile(Exe) then
    begin
      CompilerMessageWindow.AddMessage(V_Fatal,'Compiler "'+ExternalCompilerExe+'" not found','',0,0);
      Inc(status.errorCount);
      Exit;
    end;
  CmdLine:='';
  if ConfigFile<>'' then
    CmdLine:='"@'+ConfigFile+'" ';
  CmdLine:=CmdLine+'-d'+SwitchesModeStr[SwitchesMode];
  if PrimaryFileSwitches<>'' then
    CmdLine:=CmdLine+' '+PrimaryFileSwitches;
  CmdLine:=CmdLine+' '+FileName;
  status.currentsource:=FileName;
  status.compiledlines:=0;
  Aborted:=false;
  Pending:='';
  P:=TProcess.Create(nil);
  try
    P.Executable:=Exe;
    CommandToList(CmdLine,P.Parameters);
    P.Options:=[poUsePipes,poStderrToOutput,poNoConsole];
    try
      P.Execute;
    except
      on E: Exception do
        begin
          CompilerMessageWindow.AddMessage(V_Fatal,'Cannot run '+Exe+': '+E.Message,'',0,0);
          Inc(status.errorCount);
          Exit;
        end;
    end;
    repeat
      if P.Output.NumBytesAvailable>0 then
        begin
          N:=P.Output.Read(Buf,SizeOf(Buf));
          if N>0 then
            Feed(Copy(AnsiString(Buf),1,N));
        end
      else
        Sleep(10);
      { the status dialog and Esc, as for the built-in compiler }
      if Assigned(do_status) and do_status() and not Aborted then
        begin
          Aborted:=true;
          P.Terminate(1);
        end;
    until (not P.Running) and (P.Output.NumBytesAvailable=0);
    P.WaitOnExit;
    if Pending<>'' then
      Feed(Pending+#10);
    if Aborted then
      CompilationPhase:=cpAborted
    else if (P.ExitStatus<>0) and (status.errorCount=0) then
      begin
        CompilerMessageWindow.AddMessage(V_Error,'The compiler exited with code '+IntToStr(P.ExitStatus),'',0,0);
        Inc(status.errorCount);
      end;
    status.IsExe:=false;
    status.IsLibrary:=false;
    if (status.errorCount=0) and not Aborted then
      begin
        Kind:=SourceKind(MainFile);
        status.IsExe:=Kind<>'unit';
        status.IsLibrary:=Kind='library';
      end;
  finally
    P.Free;
  end;
end;

procedure Compile(const FileName, ConfigFile: string);
{$ifdef EMBED_COMPILER}
var
  cmd : string;
{$endif EMBED_COMPILER}
begin
{$ifdef EMBED_COMPILER}
  if not UseExternalCompiler then
    begin
      cmd:='-d'+SwitchesModeStr[SwitchesMode];
      if ConfigFile<>'' then
        cmd:='['+ConfigFile+'] '+cmd;
      { Add the switches from the primary file }
      if PrimaryFileSwitches<>'' then
        cmd:=cmd+' '+PrimaryFileSwitches;
      cmd:=cmd+' '+FileName;
      try
        Compiler.Compile(cmd);
      except
        on e : exception do
          begin
            CompilationPhase:=cpFailed;
            CompilerMessageWindow.AddMessage(V_Error,
              'Compiler exited','',0,0);
            CompilerMessageWindow.AddMessage(V_Error,
              e.message,'',0,0);
          end;
      end;
      Exit;
    end;
{$endif EMBED_COMPILER}
  CompileExternal(FileName,ConfigFile);
end;

procedure SetPrimaryFile(const fn:string);
var
  t : text;
begin
  PrimaryFile:='';
  PrimaryFileMain:='';
  PrimaryFileSwitches:='';
  PrimaryFilePara:='';
  if UpcaseStr(ExtOf(fn))='.PRI' then
   begin
     assign(t,fn);
     {$I-}
     reset(t);
     if ioresult=0 then
      begin
        PrimaryFile:=fn;
        readln(t,PrimaryFileMain);
        readln(t,PrimaryFileSwitches);
        readln(t,PrimaryFilePara);
        close(t);
      end;
     {$I+}
     EatIO;
   end
  else
   begin
     PrimaryFile:=fn;
     PrimaryFileMain:=fn;
   end;
  if PrimaryFilePara<>'' then
   SetRunParameters(PrimaryFilePara);
end;



end.
