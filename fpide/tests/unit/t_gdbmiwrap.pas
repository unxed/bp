program t_gdbmiwrap;
{ Tests of the GDB/MI value classes of src/gdbmiwrap.pas: a result record is parsed into tuples, lists and strings that are owned by
  the record; parsing a second line frees the first one; a malformed line does not leak the half-built values.
  The test ends with SafeCheckNoLeaks (step 4.1c of safe/FPIDE-ADOPTION.md). It needs no gdb. }
{$mode objfpc}{$H+}
uses SysUtils, GDBMIWrap, Safe;

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

begin
  TestParse;
  TestMalformed;
  SafeCheckNoLeaks;
  WriteLn(Total - Bad, '/', Total, ' checks passed');
  if Bad > 0 then Halt(1);
end.
