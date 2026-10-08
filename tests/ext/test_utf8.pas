{ Tests of ext/utf8: unit BP gives UTF-8 by default. Exit code = number of failures. }
program test_utf8;

{$mode objfpc}{$H+}

uses
  BP, SysUtils;

var
  Failed: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

begin
  WriteLn('-- UTF8');
  Check(Length('aё😀') = 7, 'utf8: Length in bytes');
  Check(CPLength('aё😀') = 3, 'utf8: CPLength in code points');
  Check(Pos('ве', 'привет') = 7, 'utf8: Pos(literal, literal) in bytes');
  Check(Copy('привет', Pos('ве', 'привет'), MaxInt) = 'вет', 'utf8: Copy from Pos');
  Check(DefaultSystemCodePage = CP_UTF8, 'utf8: DefaultSystemCodePage');
  Check(DefaultFileSystemCodePage = CP_UTF8, 'utf8: DefaultFileSystemCodePage');
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
