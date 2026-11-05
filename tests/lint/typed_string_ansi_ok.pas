// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Typed mode, #146 item 2: String is AnsiString under the H+ switch, so an array of String fits an open array of
  AnsiString, and a String variable fits a var or out AnsiString (RunCommand of the Process unit). }
unit typed_string_ansi_ok;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Process, Safe;

procedure Run(const Args: array of String; out Output: String);

implementation

procedure Take(const A: array of AnsiString);
begin
  WriteLn(Length(A));
end;

procedure TakeStrings(const A: array of String);
begin
  WriteLn(Length(A));
end;

procedure Run(const Args: array of String; out Output: String);
var
  Wide: array of String;
  Ansi: array of AnsiString;
  Line: String;
begin
  Wide := nil;
  Ansi := nil;
  SetLength(Wide, 1);
  SetLength(Ansi, 1);
  Take(Wide);
  TakeStrings(Ansi);
  Take(Args);
  Line := 'x';
  Take(['a', Line]);
  RunCommand('ls', Args, Output, [poStderrToOutPut]);
  RunCommand('ls', ['-l', Line], Output);
  RunCommand('ls', Output);
end;

end.
