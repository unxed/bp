program t_gdbmiwrap;
{ Tests of the GDB/MI value classes of src/gdbmiwrap.pas: a result record is parsed into tuples, lists and strings that are owned by
  the record; parsing a second line frees the first one; a malformed line does not leak the half-built values.
  A mock GDB also checks the guarded child-stdin command path and the pipe-based MI response read. The test ends with
  SafeCheckNoLeaks (step 4.1c of safe/FPIDE-ADOPTION.md). It needs no installed gdb. }
{$mode objfpc}{$H+}
uses SysUtils, {$ifdef unix}BaseUnix,{$endif} GDBMIWrap, GDBMIProc, GDBPty, Safe;

type
  TGDBWrapperBox = specialize TOwned<TGDBWrapper>;

var
  Bad: Integer = 0;
  Total: Integer = 0;

procedure Check(OK: Boolean; const What: string);
begin
  Inc(Total);
  if not OK then
  begin
    Inc(Bad);
    WriteLn('FAIL ', What);
  end;
end;

procedure ParseInto(AO: TGDBMI_AsyncOutput; const Line: string);
var
  P: LongInt;
begin
  P := 2;
  ParseAsyncOutput(Line, AO, P);
end;

procedure TestParse;
var
  Box: TGDBAsyncOutputBox;
  AO: TGDBMI_AsyncOutput;               { borrow: Box }
  Stack: TGDBMI_ListValue;              { borrow: AO }
begin
  Box := TGDBAsyncOutputBox.Own(TGDBMI_AsyncOutput.Create);
  AO := Box.Get;
  ParseInto(AO, '^done,bkpt={number="1",file="a.c",line="5"},' +
    'stack=[frame={level="0",addr="0x1"},frame={level="1",addr="0x2"}],names=["a","b"],empty={}');
  Check(AO.AsyncClass = 'done', 'class done');
  Check(AO.Parameters['bkpt'].AsTuple['number'].AsLongInt = 1, 'bkpt number');
  Check(AO.Parameters['bkpt'].AsTuple['file'].AsString = 'a.c', 'bkpt file');
  Stack := AO.Parameters['stack'].AsList;
  Check(Stack.Count = 2, 'stack count');
  Check(Stack.ValueAt[1].AsTuple['addr'].AsString = '0x2', 'stack frame 1 addr');
  Check(AO.Parameters['names'].AsList.Count = 2, 'names count');
  Check(AO.Parameters['names'].AsList.ValueAt[0].AsString = 'a', 'names first');
  Check(AO.Parameters['empty'].AsTuple.IsEmpty, 'empty tuple');
  Check(AO.Parameters['nosuch'] = nil, 'missing name is nil');
  { a second line replaces the first; the old values are released by Clear }
  ParseInto(AO, '*stopped,reason="breakpoint-hit"');
  Check(AO.AsyncClass = 'stopped', 'class stopped');
  Check(AO.Parameters['reason'].AsString = 'breakpoint-hit', 'reason');
  Check(AO.Parameters['bkpt'] = nil, 'old values are gone');
end;

procedure TestMalformed;
var
  Box: TGDBAsyncOutputBox;
begin
  Box := TGDBAsyncOutputBox.Own(TGDBMI_AsyncOutput.Create);
  try
    { the name "c" has no "=": the parser stops with an assertion in the middle of a tuple }
    ParseInto(Box.Get, '^done,a={b="1",c');
  except
    on Exception do ;
  end;
  { whatever happened, the values built so far belong to Box and are released with it }
end;

procedure TestGuardedGDBInput;
var
  ScriptName: string;
  Script: TextFile;
  WrapperOwner: TGDBWrapperBox;
  Wrapper: TGDBWrapper;
begin
{$ifdef unix}
  ScriptName := GetTempDir(False) + 'bp-gdbmi-' + IntToStr(fpGetPid) + '.sh';
  AssignFile(Script, ScriptName);
  Rewrite(Script);
  WriteLn(Script, '#!/bin/sh');
  WriteLn(Script, 'printf ''(gdb) \n''');
  WriteLn(Script, 'while IFS= read -r command; do');
  WriteLn(Script, '  if [ "$command" = "-gdb-exit" ]; then');
  WriteLn(Script, '    printf ''^exit\n(gdb) \n''');
  WriteLn(Script, '    exit 0');
  WriteLn(Script, '  fi');
  WriteLn(Script, '  sleep 0.1');
  WriteLn(Script, '  printf ''^done,echo="%s"\n(gdb) \n'' "$command"');
  WriteLn(Script, 'done');
  CloseFile(Script);
  try
    Check(fpChmod(PChar(ScriptName), &700) = 0, 'gdb integration: mock executable is prepared');
    GdbProgramName := ScriptName;
    WrapperOwner := TGDBWrapperBox.Own(TGDBWrapper.Create);
    Wrapper := WrapperOwner.Get;
    try
      Check(Wrapper.Alive, 'gdb integration: guarded mock process starts');
      Check(PtyOpen <> '', 'gdb integration: test PTY opens');
      PtyRelayBegin;
      try
        Wrapper.Command('-test-command');
      finally
        PtyRelayEnd;
        PtyClose;
      end;
      Check(Wrapper.ResultRecord.Success, 'gdb integration: MI result record is read');
      Check(Wrapper.ResultRecord.Parameters['echo'].AsString = '-test-command',
        'gdb integration: command reaches the child stdin through the guard');
    finally
      WrapperOwner.Reset;
      Wrapper := nil;
    end;
  finally
    fpUnlink(PChar(ScriptName));
  end;
{$else}
  WriteLn('SKIP GDB process integration: unix only');
{$endif}
end;

begin
  TestParse;
  TestMalformed;
  TestGuardedGDBInput;
  SafeCheckNoLeaks;
  WriteLn(Total - Bad, '/', Total, ' checks passed');
  if Bad > 0 then Halt(1);
end.
