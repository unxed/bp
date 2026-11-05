// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Typed mode, #146 item 5: the element S[1] of a String variable goes to an untyped var argument. }
unit typed_strelem_ok;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

procedure Exchange(const Stream: TStream; var S: String);

implementation

procedure Exchange(const Stream: TStream; var S: String);
var
  N: Integer;
begin
  SetLength(S, 8);
  N := Stream.Read(S[1], Length(S));
  Stream.ReadBuffer(S[1], N);
  Stream.WriteBuffer(S[1], Length(S));
end;

end.
