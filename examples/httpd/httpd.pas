{ SPDX-License-Identifier: MIT }
{ httpd: an HTTP/1.1 server on goroutines (SPEC §14), the scratch of each request in a region (§20, spike 2 of
  tools/spikes/region). Routes: /, /json?n=NUM (NUM squares, 0..1000, default 10), /stats. examples/httpd/README.md
  usage: httpd [PORT [WORKERS]] (default 8080 and 64); SIGTERM or SIGINT stop it, and it checks for leaks. }
program httpd;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, StrUtils, Types, BaseUnix, Sockets, SSockets, Region, BP;

type
  TConns = specialize TChan<TSocket>;
  TStreamBox = specialize TOwned<TSocketStream>;
  TServerBox = specialize TOwned<TInetServer>;

  THeader = record
    Name, Value: String;               // Name in lower case
  end;
  THeaders = specialize TGrowArray<THeader>;

  { A parsed request: an object of the current region, as are its headers. }
  TRequest = class(TRegionObject)
    Target, Version: String;
    Headers: THeaders;
    function Header(const Name: String): String;
  end;

  { Accepts connections and hands them to the workers; when the socket is shut down it tells the main thread. }
  TAcceptor = class(TTask)
    FListen: TSocket;
    FConns, FQuit: TConns;
    constructor Create(const AListen: TSocket; const AConns, AQuit: TConns);
    procedure Run; override;
  end;

  { Serves one connection at a time, with keep-alive, until the group is cancelled. }
  TWorker = class(TTask)
    FConns: TConns;
    FChunk: array of Byte;           // the read buffer
    function Fill(const Sock: TSocketStream; var Buf: String): Boolean;
    function Exchange(const Sock: TSocketStream; var Buf: String): Boolean;
    procedure Serve(const Fd: TSocket);
    constructor Create(const AConns: TConns);
    procedure Run; override;
  end;

var
  Listener: TSocket;                   // for the signal handler; written before the first task starts
  Requests, BytesSent: Int64;          // requests and bytes of response bodies: the workers touch them only through Interlocked* (S19)

function TRequest.Header(const Name: String): String;
var
  I: SizeInt;
begin
  Result := '';
  for I := 0 to Headers.Len - 1 do
    if Headers[I].Name = Name then
      Exit(Headers[I].Value);
end;

{ Parses Head (the text before the empty line) into a request of the current region; False on garbage. }
function TryParse(const Head: String; out Req: TRequest): Boolean;
var
  Lines, Parts: TStringDynArray;
  I, P: SizeInt;
  H: THeader;
begin
  Req := TRequest.Create;
  Req.Headers := THeaders.Create;
  Lines := SplitString(Head, #10);
  Parts := SplitString(Trim(Lines[0]), ' ');     // method, target, version
  Result := Length(Parts) = 3;
  SetLength(Parts, 3);
  Req.Target := Parts[1];
  Req.Version := Parts[2];
  Result := Result and (Copy(Req.Target, 1, 1) = '/') and ((Req.Version = 'HTTP/1.1') or (Req.Version = 'HTTP/1.0'));
  for I := 1 to High(Lines) do
  begin
    P := Pos(':', Lines[I]);
    Result := Result and (P > 1);
    H.Name := SysUtils.LowerCase(Trim(Copy(Lines[I], 1, P - 1)));
    H.Value := Trim(Copy(Lines[I], P + 1, MaxInt));
    Req.Headers.Push(H);
  end;
end;

{ The value of the parameter Name of a query string (a=1&b=2), or Default. }
function Param(const Query, Name, Default: String): String;
var
  Item: String;
begin
  for Item in SplitString(Query, '&') do
    if Copy(Item, 1, Length(Name) + 1) = Name + '=' then
      Exit(Copy(Item, Length(Name) + 2, MaxInt));
  Result := Default;
end;

function Squares(const N: Integer): String;
var
  I: Integer;
begin
  Result := '{"n":' + IntToStr(N) + ',"squares":[';
  for I := 1 to N do
    Result := Result + IntToStr(I * I) + ',';
  SetLength(Result, Length(Result) - Ord(N > 0));   // the last comma
  Result := Result + ']}'#10;
end;

{ Writes one response; it counts the request and the bytes of its body. }
procedure Send(const Sock: TSocketStream; const Status, CType, Body: String; const Keep: Boolean);
const
  Conn: array[Boolean] of String = ('close', 'keep-alive');
var
  S: String;
begin
  S := 'HTTP/1.1 ' + Status + #13#10'Content-Type: ' + CType + #13#10'Content-Length: ' +
    IntToStr(Length(Body)) + #13#10'Connection: ' + Conn[Keep] + #13#10#13#10 + Body;
  InterlockedIncrement64(Requests);
  InterlockedExchangeAdd64(BytesSent, Length(Body));
  Sock.WriteBuffer(S[1], Length(S));   // EWriteError when the peer has gone (TWorker.Run)
end;

procedure Route(const Sock: TSocketStream; const Req: TRequest; const Keep: Boolean);
var
  Path: String;
  N: Integer;
begin
  Path := Copy(Req.Target, 1, Pos('?', Req.Target + '?') - 1);
  if Path = '/' then
    Send(Sock, '200 OK', 'text/plain', 'Hello from Better Pascal'#10, Keep)
  else if (Path = '/json') and TryStrToInt(Param(Copy(Req.Target, Length(Path) + 2, MaxInt), 'n', '10'), N) and
    (N >= 0) and (N <= 1000) then
    Send(Sock, '200 OK', 'application/json', Squares(N), Keep)
  else if Path = '/json' then
    Send(Sock, '400 Bad Request', 'text/plain', 'n must be 0..1000'#10, Keep)
  else if Path = '/stats' then
    Send(Sock, '200 OK', 'application/json', '{"requests":' + IntToStr(InterlockedExchangeAdd64(Requests, 0)) + ',"bytes":'
      + IntToStr(InterlockedExchangeAdd64(BytesSent, 0)) + '}'#10, Keep)   // atomic reads: S19 allows a global only there
  else
    Send(Sock, '404 Not Found', 'text/plain', 'Not Found'#10, Keep);
end;

constructor TAcceptor.Create(const AListen: TSocket; const AConns, AQuit: TConns);
begin
  inherited Create;
  FListen := AListen;
  FConns := AConns;
  FQuit := AQuit;
end;

procedure TAcceptor.Run;
var
  Fd: TSocket;
begin
  repeat
    Fd := fpAccept(FListen, nil, nil);
    if Fd >= 0 then
      FConns.Send(Fd);
  until (Fd < 0) and (SocketError <> ESysEINTR) and (SocketError <> ESysECONNABORTED);
  FQuit.Send(0);
end;

constructor TWorker.Create(const AConns: TConns);
begin
  inherited Create;
  FConns := AConns;
  SetLength(FChunk, 16384);
end;

{ Reads more into Buf; False when the peer closed, after 2 idle seconds (the read timeout) or on cancellation. }
function TWorker.Fill(const Sock: TSocketStream; var Buf: String): Boolean;
var
  N, I, Old: Integer;
begin
  N := Sock.Read(FChunk[0], Length(FChunk));
  Old := Length(Buf);
  if N > 0 then
    SetLength(Buf, Old + N);
  for I := 1 to N do
    Buf[Old + I] := Char(FChunk[I - 1]);
  Result := (N > 0) and not Cancelled;
end;

{ One request (in the current region, that of Serve) and its response; False: close the connection. }
function TWorker.Exchange(const Sock: TSocketStream; var Buf: String): Boolean;
var
  Req: TRequest;
  P: SizeInt;
  Len: Int64;
  Conn: String;
begin
  Result := False;
  while Pos(#13#10#13#10, Buf) = 0 do
    if (Length(Buf) > 65536) or not Fill(Sock, Buf) then
      Exit;
  P := Pos(#13#10#13#10, Buf);
  Len := 0;
  Result := TryParse(Copy(Buf, 1, P - 1), Req) and (Req.Header('transfer-encoding') = '');
  if Result and (Req.Header('content-length') <> '') then
    Result := TryStrToInt64(Req.Header('content-length'), Len) and (Len >= 0);
  if not Result then
  begin
    Send(Sock, '400 Bad Request', 'text/plain', 'Bad Request'#10, False);
    Exit;
  end;
  Buf := Copy(Buf, P + 4, MaxInt);
  while Length(Buf) < Len do
    if not Fill(Sock, Buf) then
      Exit;
  Buf := Copy(Buf, Len + 1, MaxInt);
  Conn := SysUtils.LowerCase(Req.Header('connection'));
  Result := (Pos('close', Conn) = 0) and ((Req.Version = 'HTTP/1.1') or (Pos('keep-alive', Conn) > 0));
  Route(Sock, Req, Result);
end;

procedure TWorker.Serve(const Fd: TSocket);
var
  Sock: TStreamBox;
  R: TRegion;
  Buf: String;
begin
  Sock := TStreamBox.Own(TSocketStream.Create(Fd));   // closes the socket when Serve returns
  Sock.Get.IOTimeout := 2000;
  Sock.Get.WriteFlags := MSG_NOSIGNAL;
  Buf := '';
  R := TRegion.Create;                 // the scratch of each request; released when Serve returns
  while Exchange(Sock.Get, Buf) do
    R.Reset;                           // frees the request at once and keeps the block for the next one
end;

procedure TWorker.Run;
var
  Fd: TSocket;
begin
  repeat
    // With a timeout (-1 then loops): without one, Select overflows in a debug build (-Co, ext/go.impl.inc).
    case Select([FConns.Sel, Done], 1000) of
      0: if FConns.TryRecv(Fd) then
           try
             Serve(Fd);
           except
             on EStreamError do ;      // the peer has gone: the connection is dropped, the worker goes on
           end;
      1: Exit;                         // the group is cancelled
    end;
  until False;
end;

{ SIGTERM, SIGINT: shutting the listening socket down wakes the acceptor (accept fails), which tells the main thread. }
procedure OnSignal(Sig: LongInt); cdecl;
begin
  fpShutdown(Listener, SHUT_RDWR);
end;

procedure Main(const Port, Workers: Integer);
var
  Server: TServerBox;
  G: TGroup;
  Conns: TConns;
  Quit: TConns;
  I: Integer;
  V: TSocket;
begin
  Server := TServerBox.Own(TInetServer.Create(Port));
  Server.Get.ReuseAddress := True;
  Server.Get.QueueSize := 1024;
  Server.Get.Bind;
  Server.Get.Listen;
  Listener := Server.Get.Socket;
  fpSignal(SIGTERM, @OnSignal);
  fpSignal(SIGINT, @OnSignal);
  WriteLn('httpd: port ', Port, ', ', Workers, ' workers');
  G := TGroup.Create;
  Conns := TConns.Create(1024);
  Quit := TConns.Create(1);
  G.Go(TAcceptor.Create(Listener, Conns, Quit));
  for I := 1 to Workers do
    G.Go(TWorker.Create(Conns));
  Quit.Recv(V);
  Server.Reset;                        // closes the listening socket
  G.Cancel;
  G.Wait;
  WriteLn('httpd: ', Requests, ' requests, ', BytesSent, ' bytes');
end;

begin
  Main(StrToIntDef(ParamStr(1), 8080), StrToIntDef(ParamStr(2), 64));
  SafeCheckNoLeaks;
  WriteLn('no leaks');
end.
