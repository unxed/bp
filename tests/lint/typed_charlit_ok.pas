// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Typed mode, #146 item 3: #13#10 is a string literal, not a char: Pos(#13#10, S) is the overload for strings only. }
unit typed_charlit_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function EndOfLine(const S: String): Integer;

implementation

function EndOfLine(const S: String): Integer;
begin
  Result := Pos(#13#10, S);
  if Result = 0 then
    Result := Pos(#10, S);
  if Result = 0 then
    Result := Pos(#$0D#$0A'x', S);
end;

end.
