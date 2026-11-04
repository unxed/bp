// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@/safe -Fi@root@/safe
{ The typed mode resolves a unit with two String[N] types (the resolver once added each as a type named "string"
  to the scope: a duplicate identifier, and "string" named a ShortString after the first). }
unit typed_shortstrings_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  // UNSAFE: a fixed-size record of a file format
  TName = String[12];
  // UNSAFE: a fixed-size record of a file format
  TCode = String[3];

function Joined(const A: TName; const B: TCode): String;

implementation

function Joined(const A: TName; const B: TCode): String;
begin
  Result := A + B;
end;

end.
