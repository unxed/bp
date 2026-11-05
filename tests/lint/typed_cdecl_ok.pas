// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Typed mode, #146 item 7: a handler declared cdecl, or under the calling directive, fits the signal handler type of the
  RTL, which is cdecl. }
unit typed_cdecl_ok;

{$mode objfpc}{$H+}

interface

uses
  BaseUnix, Safe;

procedure Install;

implementation

procedure Handle(Sig: cint); cdecl;
begin
  WriteLn(Sig);
end;

{$calling cdecl}
procedure Handle2(Sig: cint);
begin
  WriteLn(Sig);
end;
{$calling default}

procedure Install;
begin
  fpSignal(SIGPIPE, @Handle);
  fpSignal(SIGPIPE, SignalHandler(@Handle));
  fpSignal(SIGUSR1, @Handle2);
end;

end.
