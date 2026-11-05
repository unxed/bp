{ SPDX-License-Identifier: MIT }
{ hello.pas with SysUtils and a formatted line: what the units most programs use add (tests/bench/size.sh). }
program hello_sysutils;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

begin
  WriteLn(Format('hello %d', [ParamCount]));
end.
