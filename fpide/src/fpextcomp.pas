{
    Free Pascal IDE on tv3: what the IDE needs to know of the compiler when the compiler is a program
    (the original gets it from the compiler's units linked into the IDE).
}
unit FPExtComp;

{$mode objfpc}{$H+}

interface

uses
  Classes;

{ the OS targets the compiler supports (fpc -it): the names as the compiler gives them, separated by #10 }
function ExternalTargets(const Exe: AnsiString): AnsiString;
{ the host the IDE runs on: tells source_info/target_info of the Systems unit }
procedure InitHostInfo;
{ $FPCVERSION, $FPCTARGET ... in a path }
procedure DefaultReplacements(var S: AnsiString);

implementation

uses
  SysUtils, TvProc, Systems;

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
  { the host is known when compiling: the choice is made by the compiler }
{$if defined(linux)}
  Name := 'Linux';
{$elseif defined(win64)}
  Name := 'Win64';
{$elseif defined(win32)}
  Name := 'Win32';
{$elseif defined(darwin)}
  Name := 'Darwin';
{$else}
  Name := HostOS;
{$endif}
{$if defined(cpux86_64)}
  Name := Name + ' for x86-64';
{$elseif defined(cpui386)}
  Name := Name + ' for i386';
{$elseif defined(cpuaarch64)}
  Name := Name + ' for AArch64';
{$else}
  Name := Name + ' for ' + HostCPU;
{$endif}
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
