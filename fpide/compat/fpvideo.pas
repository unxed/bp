{ FPVideo: the Free Vision video-mode API the IDE uses (ScreenMode as a record, SetScreenVideoMode),
  on top of tv3. tv3's ScreenMode is a mode number and a terminal cannot be switched, so the
  "current mode" is the terminal size and SetScreenVideoMode changes nothing (the IDE then shows
  its "can't set screen mode" message). Known limitation, see fpide/MIGRATION-STATUS.md. }
unit FPVideo;

{$mode objfpc}{$H-}

interface

uses
  Video;

function CurVideoMode: TVideoMode;
procedure SetScreenVideoMode(const Mode: TVideoMode);
{ Yield the CPU while the IDE is idle (FV Drivers.GiveUpTimeSlice; ThreadSwitch needs a thread driver). }
procedure GiveUpTimeSlice;

implementation

uses
  SysUtils, Drivers;

procedure GiveUpTimeSlice;
begin
  Sleep(1);
end;

function CurVideoMode: TVideoMode;
begin
  CurVideoMode.Col := ScreenWidth;
  CurVideoMode.Row := ScreenHeight;
  CurVideoMode.Color := True;
end;

procedure SetScreenVideoMode(const Mode: TVideoMode);
begin
end;

end.
