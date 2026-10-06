{
    Free Pascal IDE on tv3: what the IDE needs to know of the compiler when the compiler is a program
    (the original gets it from the compiler's units linked into the IDE).
}
unit FPExtComp;

{$mode objfpc}{$H+}

interface

uses
  Classes;

{ the whole output (stdout and stderr) of a program; '' if it could not be run }
function RunCapture(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
{ the first line of the output }
function RunFirstLine(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
{ the OS targets the compiler supports (fpc -it): the names as the compiler gives them, separated by #10 }
function ExternalTargets(const Exe: AnsiString): AnsiString;
{ the host the IDE runs on: tells source_info/target_info of the Systems unit }
procedure InitHostInfo;
{ $FPCVERSION, $FPCTARGET ... in a path }
procedure DefaultReplacements(var S: AnsiString);

implementation

uses
  SysUtils, Process, Systems;

function RunCapture(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
var
  P: TProcess;
  Buf: array[0..4095] of char;
  N, I: LongInt;
  S: AnsiString;
begin
  Result := '';
  P := TProcess.Create(nil);
  try
    P.Executable := Exe;
    for I := 0 to High(Args) do
      P.Parameters.Add(Args[I]);
    P.Options := [poUsePipes, poStderrToOutput, poNoConsole];
    try
      P.Execute;
      S := '';
      repeat
        N := P.Output.Read(Buf, SizeOf(Buf));
        if N > 0 then
        begin
          SetLength(S, Length(S) + N);
          Move(Buf, S[Length(S) - N + 1], N);
        end;
      until N <= 0;
      P.WaitOnExit;
      Result := S;
    except
      Result := '';
    end;
  finally
    P.Free;
  end;
end;

function RunFirstLine(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
var
  P: LongInt;
begin
  Result := RunCapture(Exe, Args);
  P := Pos(#10, Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  while (Result <> '') and (Result[Length(Result)] = #13) do
    Delete(Result, Length(Result), 1);
end;

function ExternalTargets(const Exe: AnsiString): AnsiString;
var
  L: TStringList;
  I: Integer;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Text := RunCapture(Exe, ['-it']);
    for I := 0 to L.Count - 1 do
      if (Trim(L[I]) <> '') and (Pos(' ', Trim(L[I])) = 0) and (Pos(':', L[I]) = 0) then
        Result := Result + Trim(L[I]) + #10;
  finally
    L.Free;
  end;
end;

const
  HostOS = {$I %FPCTARGETOS%};
  HostCPU = {$I %FPCTARGETCPU%};

procedure InitHostInfo;
var
  Name: string;
begin
  if (HostOS = 'linux') then Name := 'Linux'
  else if HostOS = 'win64' then Name := 'Win64'
  else if HostOS = 'win32' then Name := 'Win32'
  else if HostOS = 'darwin' then Name := 'Darwin'
  else Name := HostOS;
  if HostCPU = 'x86_64' then Name := Name + ' for x86-64'
  else if HostCPU = 'i386' then Name := Name + ' for i386'
  else if HostCPU = 'aarch64' then Name := Name + ' for AArch64'
  else Name := Name + ' for ' + HostCPU;
  source_info.name := Name;
  source_info.shortname := HostOS;
{$ifdef Windows}
  source_info.exeext := '.exe';
  source_info.scriptext := '.bat';
{$else}
  source_info.exeext := '';
  source_info.scriptext := '.sh';
{$endif}
  target_info := source_info;
  target_cpu_string := HostCPU;
end;


procedure DefaultReplacements(var S: AnsiString);
  procedure Replace(const Macro, Value: AnsiString);
  begin
    S := StringReplace(S, Macro, Value, [rfReplaceAll]);
  end;
begin
  Replace('$FPCTARGET', HostCPU + '-' + HostOS);
  Replace('$FPCTARGETOS', HostOS);
  Replace('$FPCTARGETCPU', HostCPU);
  Replace('$FPCCPU', HostCPU);
  Replace('$FPCOS', HostOS);
end;

end.
