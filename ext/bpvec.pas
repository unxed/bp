{ SPDX-License-Identifier: MIT }
// UNSAFE-UNIT: the kernels read and write the arrays through pointers, in SSE2 assembler on x86_64
{ BPVec: loops over whole arrays of numbers in vector instructions (SPEC §25.2, #197). FPC does not vectorize a loop
  (fpc#42043); a kernel here does it once per array: SSE2 on x86_64 (every x86_64 CPU has it), the same loop in Pascal
  on the other targets.

    uses ..., BPVec, BP;
    Axpy(Y, X, 2.0);      // Y[I] := Y[I] + 2.0 * X[I]
    S := Dot(X, Y);       // the sum of X[I] * Y[I]

  - Arrays of different lengths: a range error (ERangeError with SysUtils, run-time error 201 without).
  - Axpy, Scale, Add and Mul give the bits of the plain loop.
  - Dot and Sum add in an order of their own, the same on every target with SSE2 arithmetic (x86_64, aarch64): W
    sums S[0..W - 1] of the elements I mod W of the first N and not (W - 1) (W = 8 for Double, 16 for Single), folded
    in halves (S[J] := S[J] + S[J + W / 2], then W / 4, down to S[0] + S[1]), then the rest from the left. On i386
    (x87) the last bits may differ.
  - Integers wrap, as with overflow checks off: Add, and Sum of Int64. Sum of Int32 gives an Int64. }
unit BPVec;

{$mode objfpc}{$H+}
// -dBPVEC_PASCAL: the Pascal loops on x86_64 too
{$if defined(cpux86_64) and not defined(BPVEC_PASCAL)}{$define BPVEC_SSE2}{$asmmode att}{$endif}

interface

procedure Axpy(var Y: array of Double; const X: array of Double; const A: Double); overload; // Y[I] += A * X[I]
procedure Axpy(var Y: array of Single; const X: array of Single; const A: Single); overload;
procedure Scale(var Y: array of Double; const A: Double); overload;                            // Y[I] := Y[I] * A
procedure Scale(var Y: array of Single; const A: Single); overload;
procedure Add(var Y: array of Double; const X: array of Double); overload;                     // Y[I] += X[I]
procedure Add(var Y: array of Single; const X: array of Single); overload;
procedure Add(var Y: array of LongInt; const X: array of LongInt); overload;
procedure Add(var Y: array of Int64; const X: array of Int64); overload;
procedure Mul(var Y: array of Double; const X: array of Double); overload;                     // Y[I] := Y[I] * X[I]
procedure Mul(var Y: array of Single; const X: array of Single); overload;
function Dot(const X, Y: array of Double): Double; overload;
function Dot(const X, Y: array of Single): Single; overload;
function Sum(const X: array of Double): Double; overload;
function Sum(const X: array of Single): Single; overload;
function Sum(const X: array of LongInt): Int64; overload;
function Sum(const X: array of Int64): Int64; overload;

implementation

{$ifdef BPVEC_SSE2}
{ The kernels: (Y, X, the bytes of the part done in vectors, the address of A or nil). Each takes 32 bytes of Y and of
  X per round (Dot and Sum 64). In r9 = Y, r10 = X, r11 = bytes, rax = A on both conventions (System V and Win64); only
  registers that neither keeps are used (xmm0..xmm5). }

procedure KAxpyD(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %r9, %rax
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rcx, %rax
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  movsd  (%rax), %xmm0
  unpcklpd %xmm0, %xmm0
  xorl   %eax, %eax
.Lloop:
  movupd (%r10,%rax), %xmm1
  movupd 16(%r10,%rax), %xmm2
  mulpd  %xmm0, %xmm1
  mulpd  %xmm0, %xmm2
  movupd (%r9,%rax), %xmm3
  movupd 16(%r9,%rax), %xmm4
  addpd  %xmm1, %xmm3
  addpd  %xmm2, %xmm4
  movupd %xmm3, (%r9,%rax)
  movupd %xmm4, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

procedure KAxpyS(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %r9, %rax
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rcx, %rax
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  movss  (%rax), %xmm0
  shufps $0, %xmm0, %xmm0
  xorl   %eax, %eax
.Lloop:
  movups (%r10,%rax), %xmm1
  movups 16(%r10,%rax), %xmm2
  mulps  %xmm0, %xmm1
  mulps  %xmm0, %xmm2
  movups (%r9,%rax), %xmm3
  movups 16(%r9,%rax), %xmm4
  addps  %xmm1, %xmm3
  addps  %xmm2, %xmm4
  movups %xmm3, (%r9,%rax)
  movups %xmm4, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

procedure KScaleD(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %r9, %rax
  movq   %rcx, %r9
  movq   %r8, %r11
  {$else}
  movq   %rcx, %rax
  movq   %rdi, %r9
  movq   %rdx, %r11
  {$endif}
  movsd  (%rax), %xmm0
  unpcklpd %xmm0, %xmm0
  xorl   %eax, %eax
.Lloop:
  movupd (%r9,%rax), %xmm1
  movupd 16(%r9,%rax), %xmm2
  mulpd  %xmm0, %xmm1
  mulpd  %xmm0, %xmm2
  movupd %xmm1, (%r9,%rax)
  movupd %xmm2, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

procedure KScaleS(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %r9, %rax
  movq   %rcx, %r9
  movq   %r8, %r11
  {$else}
  movq   %rcx, %rax
  movq   %rdi, %r9
  movq   %rdx, %r11
  {$endif}
  movss  (%rax), %xmm0
  shufps $0, %xmm0, %xmm0
  xorl   %eax, %eax
.Lloop:
  movups (%r9,%rax), %xmm1
  movups 16(%r9,%rax), %xmm2
  mulps  %xmm0, %xmm1
  mulps  %xmm0, %xmm2
  movups %xmm1, (%r9,%rax)
  movups %xmm2, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

{ Y := Y op X for the packed op given by the kernel: addpd, addps, mulpd, mulps, paddd, paddq }
procedure KAddD(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorl   %eax, %eax
.Lloop:
  movupd (%r9,%rax), %xmm0
  movupd 16(%r9,%rax), %xmm1
  movupd (%r10,%rax), %xmm2
  movupd 16(%r10,%rax), %xmm3
  addpd  %xmm2, %xmm0
  addpd  %xmm3, %xmm1
  movupd %xmm0, (%r9,%rax)
  movupd %xmm1, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

procedure KAddS(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorl   %eax, %eax
.Lloop:
  movups (%r9,%rax), %xmm0
  movups 16(%r9,%rax), %xmm1
  movups (%r10,%rax), %xmm2
  movups 16(%r10,%rax), %xmm3
  addps  %xmm2, %xmm0
  addps  %xmm3, %xmm1
  movups %xmm0, (%r9,%rax)
  movups %xmm1, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

procedure KMulD(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorl   %eax, %eax
.Lloop:
  movupd (%r9,%rax), %xmm0
  movupd 16(%r9,%rax), %xmm1
  movupd (%r10,%rax), %xmm2
  movupd 16(%r10,%rax), %xmm3
  mulpd  %xmm2, %xmm0
  mulpd  %xmm3, %xmm1
  movupd %xmm0, (%r9,%rax)
  movupd %xmm1, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

procedure KMulS(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorl   %eax, %eax
.Lloop:
  movups (%r9,%rax), %xmm0
  movups 16(%r9,%rax), %xmm1
  movups (%r10,%rax), %xmm2
  movups 16(%r10,%rax), %xmm3
  mulps  %xmm2, %xmm0
  mulps  %xmm3, %xmm1
  movups %xmm0, (%r9,%rax)
  movups %xmm1, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

procedure KAddI32(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorl   %eax, %eax
.Lloop:
  movdqu (%r9,%rax), %xmm0
  movdqu 16(%r9,%rax), %xmm1
  movdqu (%r10,%rax), %xmm2
  movdqu 16(%r10,%rax), %xmm3
  paddd  %xmm2, %xmm0
  paddd  %xmm3, %xmm1
  movdqu %xmm0, (%r9,%rax)
  movdqu %xmm1, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

procedure KAddI64(Y, X: Pointer; Bytes: SizeInt; A: Pointer); assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorl   %eax, %eax
.Lloop:
  movdqu (%r9,%rax), %xmm0
  movdqu 16(%r9,%rax), %xmm1
  movdqu (%r10,%rax), %xmm2
  movdqu 16(%r10,%rax), %xmm3
  paddq  %xmm2, %xmm0
  paddq  %xmm3, %xmm1
  movdqu %xmm0, (%r9,%rax)
  movdqu %xmm1, 16(%r9,%rax)
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
end;

{ Dot and Sum: 64 bytes a round into four registers of sums, so the adds do not wait for each other; the
  registers folded in halves as the Pascal loops do }
function KDotD(X, Y: Pointer; Bytes: SizeInt; A: Pointer): Double; assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorpd  %xmm0, %xmm0
  xorpd  %xmm1, %xmm1
  xorpd  %xmm2, %xmm2
  xorpd  %xmm3, %xmm3
  xorl   %eax, %eax
.Lloop:
  movupd (%r9,%rax), %xmm4
  movupd (%r10,%rax), %xmm5
  mulpd  %xmm5, %xmm4
  addpd  %xmm4, %xmm0
  movupd 16(%r9,%rax), %xmm4
  movupd 16(%r10,%rax), %xmm5
  mulpd  %xmm5, %xmm4
  addpd  %xmm4, %xmm1
  movupd 32(%r9,%rax), %xmm4
  movupd 32(%r10,%rax), %xmm5
  mulpd  %xmm5, %xmm4
  addpd  %xmm4, %xmm2
  movupd 48(%r9,%rax), %xmm4
  movupd 48(%r10,%rax), %xmm5
  mulpd  %xmm5, %xmm4
  addpd  %xmm4, %xmm3
  addq   $64, %rax
  cmpq   %r11, %rax
  jb     .Lloop
  addpd  %xmm2, %xmm0
  addpd  %xmm3, %xmm1
  addpd  %xmm1, %xmm0
  movapd %xmm0, %xmm1
  unpckhpd %xmm1, %xmm1
  addsd  %xmm1, %xmm0
end;

function KDotS(X, Y: Pointer; Bytes: SizeInt; A: Pointer): Single; assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorps  %xmm0, %xmm0
  xorps  %xmm1, %xmm1
  xorps  %xmm2, %xmm2
  xorps  %xmm3, %xmm3
  xorl   %eax, %eax
.Lloop:
  movups (%r9,%rax), %xmm4
  movups (%r10,%rax), %xmm5
  mulps  %xmm5, %xmm4
  addps  %xmm4, %xmm0
  movups 16(%r9,%rax), %xmm4
  movups 16(%r10,%rax), %xmm5
  mulps  %xmm5, %xmm4
  addps  %xmm4, %xmm1
  movups 32(%r9,%rax), %xmm4
  movups 32(%r10,%rax), %xmm5
  mulps  %xmm5, %xmm4
  addps  %xmm4, %xmm2
  movups 48(%r9,%rax), %xmm4
  movups 48(%r10,%rax), %xmm5
  mulps  %xmm5, %xmm4
  addps  %xmm4, %xmm3
  addq   $64, %rax
  cmpq   %r11, %rax
  jb     .Lloop
  addps  %xmm2, %xmm0
  addps  %xmm3, %xmm1
  addps  %xmm1, %xmm0
  movhlps %xmm0, %xmm1
  addps  %xmm1, %xmm0
  movaps %xmm0, %xmm1
  shufps $0x55, %xmm1, %xmm1
  addss  %xmm1, %xmm0
end;

function KSumD(X, Y: Pointer; Bytes: SizeInt; A: Pointer): Double; assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorpd  %xmm0, %xmm0
  xorpd  %xmm1, %xmm1
  xorpd  %xmm2, %xmm2
  xorpd  %xmm3, %xmm3
  xorl   %eax, %eax
.Lloop:
  movupd (%r9,%rax), %xmm4
  addpd  %xmm4, %xmm0
  movupd 16(%r9,%rax), %xmm4
  addpd  %xmm4, %xmm1
  movupd 32(%r9,%rax), %xmm4
  addpd  %xmm4, %xmm2
  movupd 48(%r9,%rax), %xmm4
  addpd  %xmm4, %xmm3
  addq   $64, %rax
  cmpq   %r11, %rax
  jb     .Lloop
  addpd  %xmm2, %xmm0
  addpd  %xmm3, %xmm1
  addpd  %xmm1, %xmm0
  movapd %xmm0, %xmm1
  unpckhpd %xmm1, %xmm1
  addsd  %xmm1, %xmm0
end;

function KSumS(X, Y: Pointer; Bytes: SizeInt; A: Pointer): Single; assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %rdx, %r10
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rsi, %r10
  movq   %rdx, %r11
  {$endif}
  xorps  %xmm0, %xmm0
  xorps  %xmm1, %xmm1
  xorps  %xmm2, %xmm2
  xorps  %xmm3, %xmm3
  xorl   %eax, %eax
.Lloop:
  movups (%r9,%rax), %xmm4
  addps  %xmm4, %xmm0
  movups 16(%r9,%rax), %xmm4
  addps  %xmm4, %xmm1
  movups 32(%r9,%rax), %xmm4
  addps  %xmm4, %xmm2
  movups 48(%r9,%rax), %xmm4
  addps  %xmm4, %xmm3
  addq   $64, %rax
  cmpq   %r11, %rax
  jb     .Lloop
  addps  %xmm2, %xmm0
  addps  %xmm3, %xmm1
  addps  %xmm1, %xmm0
  movhlps %xmm0, %xmm1
  addps  %xmm1, %xmm0
  movaps %xmm0, %xmm1
  shufps $0x55, %xmm1, %xmm1
  addss  %xmm1, %xmm0
end;

{ the Int32 widened to Int64 by their sign (punpck with the sign mask), summed in two pairs of lanes }
function KSumI32(X, Y: Pointer; Bytes: SizeInt; A: Pointer): Int64; assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rdx, %r11
  {$endif}
  pxor   %xmm0, %xmm0
  pxor   %xmm1, %xmm1
  xorl   %eax, %eax
.Lloop:
  movdqu (%r9,%rax), %xmm2
  movdqa %xmm2, %xmm3
  psrad  $31, %xmm3
  movdqa %xmm2, %xmm4
  punpckldq %xmm3, %xmm2
  punpckhdq %xmm3, %xmm4
  paddq  %xmm2, %xmm0
  paddq  %xmm4, %xmm1
  addq   $16, %rax
  cmpq   %r11, %rax
  jb     .Lloop
  paddq  %xmm1, %xmm0
  pshufd $0x4e, %xmm0, %xmm1
  paddq  %xmm1, %xmm0
  movq   %xmm0, %rax
end;

function KSumI64(X, Y: Pointer; Bytes: SizeInt; A: Pointer): Int64; assembler; nostackframe;
asm
  {$ifdef WIN64}
  movq   %rcx, %r9
  movq   %r8, %r11
  {$else}
  movq   %rdi, %r9
  movq   %rdx, %r11
  {$endif}
  pxor   %xmm0, %xmm0
  pxor   %xmm1, %xmm1
  xorl   %eax, %eax
.Lloop:
  movdqu (%r9,%rax), %xmm2
  movdqu 16(%r9,%rax), %xmm3
  paddq  %xmm2, %xmm0
  paddq  %xmm3, %xmm1
  addq   $32, %rax
  cmpq   %r11, %rax
  jb     .Lloop
  paddq  %xmm1, %xmm0
  pshufd $0x4e, %xmm0, %xmm1
  paddq  %xmm1, %xmm0
  movq   %xmm0, %rax
end;
{$endif BPVEC_SSE2}

{ a range error at the caller: ERangeError with SysUtils (through ErrorProc, as a checked index raises it), else
  run-time error 201 }
procedure LengthError;
begin
  if ErrorProc <> nil then
    ErrorProc(201, nil, nil);
  RunError(201);
end;

procedure SameLength(const N, M: SizeInt); inline;
begin
  if N <> M then
    LengthError;
end;

{$push}{$Q-}{$R-} // the integer kernels wrap; the indexes are checked by the lengths

procedure Axpy(var Y: array of Double; const X: array of Double; const A: Double);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  SameLength(N, Length(X));
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 3;
  if I > 0 then
    KAxpyD(@Y[0], @X[0], I * SizeOf(Double), @A);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] + A * X[I];
    Inc(I);
  end;
end;

procedure Axpy(var Y: array of Single; const X: array of Single; const A: Single);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  SameLength(N, Length(X));
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 7;
  if I > 0 then
    KAxpyS(@Y[0], @X[0], I * SizeOf(Single), @A);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] + A * X[I];
    Inc(I);
  end;
end;

procedure Scale(var Y: array of Double; const A: Double);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 3;
  if I > 0 then
    KScaleD(@Y[0], nil, I * SizeOf(Double), @A);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] * A;
    Inc(I);
  end;
end;

procedure Scale(var Y: array of Single; const A: Single);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 7;
  if I > 0 then
    KScaleS(@Y[0], nil, I * SizeOf(Single), @A);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] * A;
    Inc(I);
  end;
end;

procedure Add(var Y: array of Double; const X: array of Double);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  SameLength(N, Length(X));
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 3;
  if I > 0 then
    KAddD(@Y[0], @X[0], I * SizeOf(Double), nil);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] + X[I];
    Inc(I);
  end;
end;

procedure Add(var Y: array of Single; const X: array of Single);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  SameLength(N, Length(X));
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 7;
  if I > 0 then
    KAddS(@Y[0], @X[0], I * SizeOf(Single), nil);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] + X[I];
    Inc(I);
  end;
end;

procedure Add(var Y: array of LongInt; const X: array of LongInt);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  SameLength(N, Length(X));
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 7;
  if I > 0 then
    KAddI32(@Y[0], @X[0], I * SizeOf(LongInt), nil);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] + X[I];
    Inc(I);
  end;
end;

procedure Add(var Y: array of Int64; const X: array of Int64);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  SameLength(N, Length(X));
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 3;
  if I > 0 then
    KAddI64(@Y[0], @X[0], I * SizeOf(Int64), nil);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] + X[I];
    Inc(I);
  end;
end;

procedure Mul(var Y: array of Double; const X: array of Double);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  SameLength(N, Length(X));
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 3;
  if I > 0 then
    KMulD(@Y[0], @X[0], I * SizeOf(Double), nil);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] * X[I];
    Inc(I);
  end;
end;

procedure Mul(var Y: array of Single; const X: array of Single);
var
  I, N: SizeInt;
begin
  N := Length(Y);
  SameLength(N, Length(X));
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 7;
  if I > 0 then
    KMulS(@Y[0], @X[0], I * SizeOf(Single), nil);
  {$endif}
  while I < N do
  begin
    Y[I] := Y[I] * X[I];
    Inc(I);
  end;
end;

function Dot(const X, Y: array of Double): Double;
var
  I, N: SizeInt;
  {$ifndef BPVEC_SSE2}
  S0, S1, S2, S3, S4, S5, S6, S7: Double;
  {$endif}
begin
  N := Length(X);
  SameLength(N, Length(Y));
  {$ifdef BPVEC_SSE2}
  I := N and not 7;
  Result := 0;
  if I > 0 then
    Result := KDotD(@X[0], @Y[0], I * SizeOf(Double), nil);
  {$else}
  S0 := 0;
  S1 := 0;
  S2 := 0;
  S3 := 0;
  S4 := 0;
  S5 := 0;
  S6 := 0;
  S7 := 0;
  I := 0;
  while I + 8 <= N do
  begin
    S0 := S0 + X[I + 0] * Y[I + 0];
    S1 := S1 + X[I + 1] * Y[I + 1];
    S2 := S2 + X[I + 2] * Y[I + 2];
    S3 := S3 + X[I + 3] * Y[I + 3];
    S4 := S4 + X[I + 4] * Y[I + 4];
    S5 := S5 + X[I + 5] * Y[I + 5];
    S6 := S6 + X[I + 6] * Y[I + 6];
    S7 := S7 + X[I + 7] * Y[I + 7];
    Inc(I, 8);
  end;
  // folded in halves
  S0 := S0 + S4;
  S1 := S1 + S5;
  S2 := S2 + S6;
  S3 := S3 + S7;
  S0 := S0 + S2;
  S1 := S1 + S3;
  S0 := S0 + S1;
  Result := S0;
  {$endif}
  while I < N do
  begin
    Result := Result + X[I] * Y[I];
    Inc(I);
  end;
end;

function Dot(const X, Y: array of Single): Single;
var
  I, N: SizeInt;
  {$ifndef BPVEC_SSE2}
  S0, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, S15: Single;
  {$endif}
begin
  N := Length(X);
  SameLength(N, Length(Y));
  {$ifdef BPVEC_SSE2}
  I := N and not 15;
  Result := 0;
  if I > 0 then
    Result := KDotS(@X[0], @Y[0], I * SizeOf(Single), nil);
  {$else}
  S0 := 0;
  S1 := 0;
  S2 := 0;
  S3 := 0;
  S4 := 0;
  S5 := 0;
  S6 := 0;
  S7 := 0;
  S8 := 0;
  S9 := 0;
  S10 := 0;
  S11 := 0;
  S12 := 0;
  S13 := 0;
  S14 := 0;
  S15 := 0;
  I := 0;
  while I + 16 <= N do
  begin
    S0 := S0 + X[I + 0] * Y[I + 0];
    S1 := S1 + X[I + 1] * Y[I + 1];
    S2 := S2 + X[I + 2] * Y[I + 2];
    S3 := S3 + X[I + 3] * Y[I + 3];
    S4 := S4 + X[I + 4] * Y[I + 4];
    S5 := S5 + X[I + 5] * Y[I + 5];
    S6 := S6 + X[I + 6] * Y[I + 6];
    S7 := S7 + X[I + 7] * Y[I + 7];
    S8 := S8 + X[I + 8] * Y[I + 8];
    S9 := S9 + X[I + 9] * Y[I + 9];
    S10 := S10 + X[I + 10] * Y[I + 10];
    S11 := S11 + X[I + 11] * Y[I + 11];
    S12 := S12 + X[I + 12] * Y[I + 12];
    S13 := S13 + X[I + 13] * Y[I + 13];
    S14 := S14 + X[I + 14] * Y[I + 14];
    S15 := S15 + X[I + 15] * Y[I + 15];
    Inc(I, 16);
  end;
  // folded in halves
  S0 := S0 + S8;
  S1 := S1 + S9;
  S2 := S2 + S10;
  S3 := S3 + S11;
  S4 := S4 + S12;
  S5 := S5 + S13;
  S6 := S6 + S14;
  S7 := S7 + S15;
  S0 := S0 + S4;
  S1 := S1 + S5;
  S2 := S2 + S6;
  S3 := S3 + S7;
  S0 := S0 + S2;
  S1 := S1 + S3;
  S0 := S0 + S1;
  Result := S0;
  {$endif}
  while I < N do
  begin
    Result := Result + X[I] * Y[I];
    Inc(I);
  end;
end;

function Sum(const X: array of Double): Double;
var
  I, N: SizeInt;
  {$ifndef BPVEC_SSE2}
  S0, S1, S2, S3, S4, S5, S6, S7: Double;
  {$endif}
begin
  N := Length(X);
  {$ifdef BPVEC_SSE2}
  I := N and not 7;
  Result := 0;
  if I > 0 then
    Result := KSumD(@X[0], nil, I * SizeOf(Double), nil);
  {$else}
  S0 := 0;
  S1 := 0;
  S2 := 0;
  S3 := 0;
  S4 := 0;
  S5 := 0;
  S6 := 0;
  S7 := 0;
  I := 0;
  while I + 8 <= N do
  begin
    S0 := S0 + X[I + 0];
    S1 := S1 + X[I + 1];
    S2 := S2 + X[I + 2];
    S3 := S3 + X[I + 3];
    S4 := S4 + X[I + 4];
    S5 := S5 + X[I + 5];
    S6 := S6 + X[I + 6];
    S7 := S7 + X[I + 7];
    Inc(I, 8);
  end;
  // folded in halves
  S0 := S0 + S4;
  S1 := S1 + S5;
  S2 := S2 + S6;
  S3 := S3 + S7;
  S0 := S0 + S2;
  S1 := S1 + S3;
  S0 := S0 + S1;
  Result := S0;
  {$endif}
  while I < N do
  begin
    Result := Result + X[I];
    Inc(I);
  end;
end;

function Sum(const X: array of Single): Single;
var
  I, N: SizeInt;
  {$ifndef BPVEC_SSE2}
  S0, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, S15: Single;
  {$endif}
begin
  N := Length(X);
  {$ifdef BPVEC_SSE2}
  I := N and not 15;
  Result := 0;
  if I > 0 then
    Result := KSumS(@X[0], nil, I * SizeOf(Single), nil);
  {$else}
  S0 := 0;
  S1 := 0;
  S2 := 0;
  S3 := 0;
  S4 := 0;
  S5 := 0;
  S6 := 0;
  S7 := 0;
  S8 := 0;
  S9 := 0;
  S10 := 0;
  S11 := 0;
  S12 := 0;
  S13 := 0;
  S14 := 0;
  S15 := 0;
  I := 0;
  while I + 16 <= N do
  begin
    S0 := S0 + X[I + 0];
    S1 := S1 + X[I + 1];
    S2 := S2 + X[I + 2];
    S3 := S3 + X[I + 3];
    S4 := S4 + X[I + 4];
    S5 := S5 + X[I + 5];
    S6 := S6 + X[I + 6];
    S7 := S7 + X[I + 7];
    S8 := S8 + X[I + 8];
    S9 := S9 + X[I + 9];
    S10 := S10 + X[I + 10];
    S11 := S11 + X[I + 11];
    S12 := S12 + X[I + 12];
    S13 := S13 + X[I + 13];
    S14 := S14 + X[I + 14];
    S15 := S15 + X[I + 15];
    Inc(I, 16);
  end;
  // folded in halves
  S0 := S0 + S8;
  S1 := S1 + S9;
  S2 := S2 + S10;
  S3 := S3 + S11;
  S4 := S4 + S12;
  S5 := S5 + S13;
  S6 := S6 + S14;
  S7 := S7 + S15;
  S0 := S0 + S4;
  S1 := S1 + S5;
  S2 := S2 + S6;
  S3 := S3 + S7;
  S0 := S0 + S2;
  S1 := S1 + S3;
  S0 := S0 + S1;
  Result := S0;
  {$endif}
  while I < N do
  begin
    Result := Result + X[I];
    Inc(I);
  end;
end;

function Sum(const X: array of LongInt): Int64;
var
  I, N: SizeInt;
begin
  N := Length(X);
  Result := 0;
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 3;
  if I > 0 then
    Result := KSumI32(@X[0], nil, I * SizeOf(LongInt), nil);
  {$endif}
  while I < N do
  begin
    Result := Result + X[I];
    Inc(I);
  end;
end;

function Sum(const X: array of Int64): Int64;
var
  I, N: SizeInt;
begin
  N := Length(X);
  Result := 0;
  I := 0;
  {$ifdef BPVEC_SSE2}
  I := N and not 3;
  if I > 0 then
    Result := KSumI64(@X[0], nil, I * SizeOf(Int64), nil);
  {$endif}
  while I < N do
  begin
    Result := Result + X[I];
    Inc(I);
  end;
end;

{$pop}

end.
