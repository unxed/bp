// EXPECT: clean
{ Parser: fcl-passrc 3.2.2 stops with a Fatal on the directive nostackframe of an assembler routine
  (ext/bpthreads.pas); bpvet skips it in any letter case and with blanks before the semicolon, so the module
  is parsed and checked to its end. }
unit parse_nostackframe;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function Seven: LongInt;
function Eight: LongInt;

implementation

function Seven: LongInt; assembler; nostackframe;
asm
  movl   $7, %eax
end;

function Eight: LongInt;
  assembler; NoStackFrame ;
asm
  movl   $8, %eax
end;

end.
