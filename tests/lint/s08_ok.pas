// EXPECT: clean
{ S8: the full name of a poisoned routine is marked with // UNSAFE: on the line above; full names in comments
  and strings (SysUtils.FreeAndNil, System.Move) are not code. }
unit s08_ok;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Safe;

procedure Drop(var List: TStringList);

implementation

procedure Drop(var List: TStringList);
begin
  WriteLn('System.Move is not called here');
  // UNSAFE: List is a borrow that nobody else owns; the caller passes the only reference and gets nil back
  SysUtils.FreeAndNil(List);
end;

end.
