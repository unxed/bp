// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ H20 (unxed/bp#207): a nested routine with a const parameter bound to a local of its parent is fine when it writes
  another local, or only reads that one; a value parameter holds its own reference. }
unit h20_ok;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Outer: SizeInt;

implementation

function Outer: SizeInt;
var
  X, Other: String;

  function WritesOther(const S: String): SizeInt;
  begin
    Other := S + '!';
    Result := Length(S);
  end;

  function ReadsX(const S: String): SizeInt;
  begin
    Result := Length(S) + Length(X);
  end;

  // UNSAFE: a value parameter, on purpose: it holds its own reference, so the write of X below does not free it
  procedure Takes(S: String);
  begin
    X := '';
    Other := S;
  end;

begin
  X := 'abc';
  Other := '';
  Result := WritesOther(X) + ReadsX(X);
  Takes(X);
  Result := Result + Length(Other);
end;

end.
