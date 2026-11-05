x86_64: LongInt array index is copied to a scratch register before every use (swap loop: 12 instructions instead of 8)

## Summary

On x86_64, when an array is indexed by a `LongInt` variable that lives in a register, FPC copies the variable
into another register (`movl %edx,%esi`) before every memory operand that uses it, although the 32-bit register
already has its upper half cleared by the last write (`addl`, `subl`, `xorl`). In a loop that swaps two array
elements this gives 12 instructions per iteration; with `SizeInt` index variables or with pointers FPC emits the
expected 8. No `-O` level, `-Cp` or `-Oo` switch removes the copies.

The copies cost about 25% in a loop that swaps many elements (the reversal of an array, as in the fannkuch
benchmark). The same loop with `SizeInt` indexes is faster than gcc's.

## Versions and options

- FPC 3.2.2 (Ubuntu 3.2.2+dfsg-32, x86_64-linux); trunk 3.3.1 [2024/08/22]; trunk 3.3.1 [2026/11/05] (main at
  d7965e4b, x86_64-linux).
- `fpc -O3 -al repro.pas`; also `-O2`, `-O4`, `-O3 -CpCOREI`, `-O3 -OoLOOPUNROLL`, `-O3 -Cr-`,
  `-O4 -CpCOREI -OoLOOPUNROLL -Cr-`: the loop is the same in all of them.
- Reference: gcc 13.3.0 `gcc -O2`, same program in C; `int32_t` there, `LongInt` in Pascal (both 32-bit).
- Intel Core i5-6300U, Linux 6.8.0.

## The program

`repro.pas` (attached, 45 lines; `repro.c` is the same in C):

```pascal
const
  N = 256;
type
  TArr = array[0..N - 1] of LongInt;

function Run(Rounds: LongInt): LongInt;
var
  A: TArr;
  R, I, J, T: LongInt;
begin
  for I := 0 to N - 1 do
    A[I] := I;
  Result := 0;
  for R := 1 to Rounds do
  begin
    I := 0;
    J := R and (N - 1);
    while I < J do
    begin
      T := A[I];
      A[I] := A[J];
      A[J] := T;
      Inc(I);
      Dec(J);
    end;
    Result := Result + A[0];
  end;
end;
```

`repro_idx64.pas` is the same with `I, J: SizeInt`; `repro_ptr.pas` walks two `PLongInt` pointers instead.

## The generated code of the inner loop

FPC 3.2.2 `-O3` (trunk 3.3.1 [2024/08/22] and main at d7965e4b [2026/11/05] give the same 12 instructions):

```asm
.Lj13:
# [28] T := A[I];
	movl	%edx,%esi                  # copy of I
	movl	(%rsp,%rsi,4),%r10d
# [29] A[I] := A[J];
	movl	%edx,%esi                  # copy of I again
	movl	%r8d,%r9d                  # copy of J
	movl	(%rsp,%r9,4),%r9d
	movl	%r9d,(%rsp,%rsi,4)
# [30] A[J] := T;
	movl	%r8d,%esi                  # copy of J again
	movl	%r10d,(%rsp,%rsi,4)
# [31] Inc(I);
	addl	$1,%edx
# [32] Dec(J);
	subl	$1,%r8d
.Lj14:
	cmpl	%edx,%r8d
	jg	.Lj13
```

The four marked `movl reg32,reg32` only zero-extend the index into a 64-bit register. `%edx` and `%r8d` are
written only by 32-bit instructions, so `%rdx` and `%r8` already hold the zero-extended values and can be used as
the index register directly.

Expected (this is what FPC itself emits for `repro_idx64.pas`, `SizeInt` indexes, `-O3`; `repro_ptr.pas` gives the
same shape with pointers):

```asm
.Lj13:
	movl	(%rsp,%rdx,4),%r9d
	movl	(%rsp,%r8,4),%esi
	movl	%esi,(%rsp,%rdx,4)
	movl	%r9d,(%rsp,%r8,4)
	addq	$1,%rdx
	subq	$1,%r8
.Lj14:
	cmpq	%rdx,%r8
	jg	.Lj13
```

For reference, gcc 13 `-O2` on `repro.c` (11 instructions: two moving pointers plus a recomputed counter):

```asm
.L5:
	movl	(%rdx), %esi
	movl	(%rcx), %edi
	subl	$1, %eax
	addq	$4, %rdx
	subq	$4, %rcx
	movl	%edi, -4(%rdx)
	movl	%esi, 4(%rcx)
	movl	%r8d, %esi
	subl	%eax, %esi
	cmpl	%esi, %eax
	jg	.L5
```

## Timings

`./prog` with the default 10,000,000 rounds (an average of 64 swaps per round); median wall time of 5 runs, the
programs run in turn; every program prints `1275000255`.

| program | compiler and options | instructions per swap | time |
|---|---|---|---|
| repro.pas | FPC 3.2.2 `-O3` | 12 | 0.722 s |
| repro.pas | FPC 3.2.2 `-O4` | 12 | 0.722 s |
| repro.pas | FPC 3.2.2 `-O3 -CpCOREI` | 12 | 0.733 s |
| repro.pas | FPC 3.2.2 `-O3 -OoLOOPUNROLL` | 12 | 0.725 s |
| repro.pas | FPC 3.2.2 `-O3 -Cr-` | 12 | 0.730 s |
| repro.pas | FPC 3.2.2 `-O4 -CpCOREI -OoLOOPUNROLL -Cr-` | 12 | 0.723 s |
| repro.pas | FPC 3.3.1 [2024/08/22] `-O3` | 12 | 0.722 s |
| repro.pas | FPC 3.3.1 [2024/08/22] `-O4 -CpCOREI -OoLOOPUNROLL -Cr-` | 12 | 0.723 s |
| repro_idx64.pas | FPC 3.2.2 `-O3` | 8 | 0.584 s |
| repro_idx64.pas | FPC 3.3.1 [2024/08/22] `-O3` | 8 | 0.575 s |
| repro_ptr.pas | FPC 3.2.2 `-O3` | 8 | 0.543 s |
| repro.c | gcc 13.3.0 `-O2` | 11 | 0.660 s |
| repro.c | gcc 13.3.0 `-O3` | 11 | 0.661 s |

With `N = 16` (at most 8 swaps per round, the size of the fannkuch benchmark) the loop is bound by its exit branch
and the three Pascal variants run equally fast (0.77 s for 150,000,000 rounds; gcc `-O2` 0.70 s), so the copies
matter in longer loops.

The same with main at d7965e4b [2026/11/05], `-O3`, on an Intel Xeon Platinum 8260 (a virtual machine, so the
times are not comparable with the table above):

| program | compiler and options | instructions per swap | time |
|---|---|---|---|
| repro.pas | FPC 3.3.1 [2026/11/05] `-O3` | 12 | 0.71 s |
| repro_idx64.pas | FPC 3.3.1 [2026/11/05] `-O3` | 8 | 0.55 s |
| repro.c | gcc 13.3.0 `-O2` | 11 | 0.63 s |
