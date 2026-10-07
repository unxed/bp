{ A pseudo terminal for the program run by the debugger.

  gdb starts the debuggee on the terminal it is told with `-inferior-tty-set`. The terminal of the IDE cannot be
  given: it is already the controlling terminal of the session of the IDE, so gdb's TIOCSCTTY fails and gdb
  writes "Failed to set controlling terminal" onto it. So the debuggee gets a terminal of its own (this
  unit), and while it runs the IDE copies its output to the real terminal and the keys back, like script(1) does. }
unit GdbPty;

{$mode objfpc}{$H+}

interface

{ the master side is opened; the name of the slave side for `-inferior-tty-set`, '' if there is no pty here }
function PtyOpen: string;
procedure PtyClose;
function PtyActive: boolean;

{ the real terminal goes raw and the debuggee's terminal gets its size; PtyRelayEnd puts the terminal back }
procedure PtyRelayBegin;
procedure PtyRelayEnd;

{ waits until `fd` (gdb's output) can be read; meanwhile the output of the debuggee goes to the screen and the
  keyboard to the debuggee. False if `fd` hung up. }
function PtyWait(fd: longint): boolean;

implementation

{$ifdef Unix}
uses
  BaseUnix, Termio, ctypes;

const
  O_RDWR_ = 2;
  O_NOCTTY_ = {$ifdef Linux}$100{$else}$20000{$endif};

function posix_openpt(flags: cint): cint; cdecl; external 'c' name 'posix_openpt';
function grantpt(fd: cint): cint; cdecl; external 'c' name 'grantpt';
function unlockpt(fd: cint): cint; cdecl; external 'c' name 'unlockpt';
function ptsname(fd: cint): PChar; cdecl; external 'c' name 'ptsname';

var
  Master: cint = -1;
  Saved: Termios;
  SavedOk: boolean = false;
  MasterOpen: boolean = false;       { the master can be read: false after the debuggee closed its end }
  Relaying: boolean = false;

function PtyOpen: string;
var
  p: PChar;
begin
  Result := '';
  if Master >= 0 then
    Exit(StrPas(ptsname(Master)));
  Master := posix_openpt(O_RDWR_ or O_NOCTTY_);
  if Master < 0 then
    Exit;
  if (grantpt(Master) <> 0) or (unlockpt(Master) <> 0) then
  begin
    fpClose(Master);
    Master := -1;
    Exit;
  end;
  p := ptsname(Master);
  if p = nil then
  begin
    fpClose(Master);
    Master := -1;
    Exit;
  end;
  Result := StrPas(p);
end;

procedure PtyClose;
begin
  if Master >= 0 then
    fpClose(Master);
  Master := -1;
end;

function PtyActive: boolean;
begin
  Result := Master >= 0;
end;

procedure PtyRelayBegin;
var
  raw: Termios;
  ws: TWinSize;
begin
  if Master < 0 then
    Exit;
  MasterOpen := true;
  Relaying := true;
  if (TCGetAttr(0, Saved) = 0) then
  begin
    SavedOk := true;
    raw := Saved;
    CFMakeRaw(raw);
    TCSetAttr(0, TCSANOW, raw);
  end;
  if fpIOCtl(1, TIOCGWINSZ, @ws) = 0 then
    fpIOCtl(Master, TIOCSWINSZ, @ws);
end;

{ what the debuggee wrote last must reach the screen before the IDE takes the terminal back }
procedure DrainMaster;
var
  pfd: TPollFD;
  buf: array[0..4095] of byte;
  r: ssize_t;
  n: longint;
begin
  if (Master < 0) or not MasterOpen then
    Exit;
  for n := 1 to 64 do
  begin
    pfd.fd := Master; pfd.events := POLLIN; pfd.revents := 0;
    if fpPoll(@pfd, 1, 50) <= 0 then
      Break;
    r := fpRead(Master, buf, SizeOf(buf));
    if r <= 0 then
    begin
      if r = 0 then
        MasterOpen := false;
      Break;
    end;
    fpWrite(1, buf, r);
  end;
end;

procedure PtyRelayEnd;
begin
  if Relaying then
    DrainMaster;
  Relaying := false;
  if SavedOk then
    TCSetAttr(0, TCSANOW, Saved);
  SavedOk := false;
end;

function PtyWait(fd: longint): boolean;
var
  fds: array[0..2] of TPollFD;
  n, i: longint;
  buf: array[0..4095] of byte;
  r: ssize_t;
begin
  Result := true;
  if not Relaying then
    Exit;                                  { nothing to relay: the caller just reads }
  repeat
    fds[0].fd := fd;      fds[0].events := POLLIN; fds[0].revents := 0;
    n := 1;
    if MasterOpen then
    begin
      fds[1].fd := Master; fds[1].events := POLLIN; fds[1].revents := 0;
      fds[2].fd := 0;      fds[2].events := POLLIN; fds[2].revents := 0;
      n := 3;
    end;
    i := fpPoll(@fds[0], n, -1);
    if i < 0 then
    begin
      if fpgeterrno = ESysEINTR then
        Continue;
      Exit;
    end;
    if ((fds[0].revents and (POLLIN or POLLHUP or POLLERR)) <> 0) and
       not (MasterOpen and ((fds[1].revents and POLLIN) <> 0)) then
      Exit(true);                          { gdb has something (and the debuggee has not): back to the reader }
    if MasterOpen then
    begin
      if (fds[1].revents and (POLLIN or POLLHUP or POLLERR)) <> 0 then
      begin
        r := fpRead(Master, buf, SizeOf(buf));
        if r > 0 then
          fpWrite(1, buf, r)
        else if (r = 0) or (fpgeterrno <> ESysEINTR) and (fpgeterrno <> ESysEAGAIN) then
          MasterOpen := false;             { EIO: the debuggee is gone; gdb will say so }
      end;
      if (fds[2].revents and POLLIN) <> 0 then
      begin
        r := fpRead(0, buf, SizeOf(buf));
        if r > 0 then
          fpWrite(Master, buf, r);
      end;
    end;
  until false;
end;

{$else}
function PtyOpen: string;
begin
  Result := '';
end;

procedure PtyClose;
begin
end;

function PtyActive: boolean;
begin
  Result := false;
end;

procedure PtyRelayBegin;
begin
end;

procedure PtyRelayEnd;
begin
end;

function PtyWait(fd: longint): boolean;
begin
  Result := true;
end;
{$endif}

end.
