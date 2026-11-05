// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Typed mode, #146 item 4: Delete and Insert take a String variable (FPC has them as compiler procedures). }
unit typed_strdelete_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

procedure Edit(var S: String; const T: AnsiString);

implementation

procedure Edit(var S: String; const T: AnsiString);
begin
  Delete(S, 1, 1);
  Insert('x', S, 1);
  Insert(T, S, 2);
  Insert(T + T, S, 2);
  Delete(S, 1, Pos('x', S));
end;

end.
