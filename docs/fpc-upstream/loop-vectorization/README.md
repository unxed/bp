x86_64: simple loops over arrays are not vectorized (Y[I] := Y[I] + A * X[I]: 1.9x slower than gcc -O3)

Filed 2026-11-05 as https://gitlab.com/freepascal.org/fpc/source/-/issues/42043 (here: #192, part of #185).

## Summary

FPC compiles a loop over arrays of `Double` one element per instruction (`mulsd`, `addsd`). gcc -O3 does two
elements per SSE2 instruction (`mulpd`, `addpd`), after a run-time check that the two arrays do not overlap in a way
that matters. On the loop below FPC takes 1.58 s and gcc -O3 0.83 s. gcc -O2 (whose vectorizer, on since GCC 12,
adds no run-time checks) vectorizes the loop only where it can see that the arrays are distinct, for example after
inlining a routine on two global arrays (0.83 s, `-DINLINE` below); in the routine on its own it stays scalar. The
scalar code of FPC is as good as gcc's, so the gap is the vectorization.

No FPC option changes the loop: `-O4`, `-CfAVX2 -CpCOREAVX2` (1.84 s, the same scalar loop in VEX form). Related:
#39612 (`-Sv` generates scalar instructions) and #40973 (the state of SIMD intrinsics); this report is about loops
written in plain Pascal.

Found in the benchmarks of Better Pascal (https://github.com/unxed/bp), a safe dialect of Object Pascal that builds
with stock FPC: n-body there runs at 1.36x of gcc, and gcc's vectorizer accounts for part of it (gcc -O2 against
`-fno-tree-vectorize` on the n-body inner loop: 0.35 s against 0.40 s).

## Versions and options

- FPC 3.2.2 (Ubuntu 3.2.2+dfsg-32, x86_64-linux) and main at d7965e4b, 3.3.1 [2026/11/05], x86_64-linux with
  `-O4`: the same scalar loop.
- `fpc -O3 -al repro.pas`; also `-O4`, `-O3 -CfAVX2 -CpCOREAVX2`.
- Reference: gcc 13.3.0 `-O3` and `-O2` on `repro.c` (no `restrict`, the routine marked `noipa`, so gcc knows no
  more about the arrays than FPC does).
- Intel Core i5-6300U, Linux 6.8.0.

## The program

`repro.pas` (attached; `repro.c` is the same in C):

```pascal
const
  N = 1024;
type
  TVec = array[0..N - 1] of Double;

procedure Axpy(var Y: TVec; const X: TVec; const A: Double);
var
  I: SizeInt;
begin
  for I := 0 to N - 1 do
    Y[I] := Y[I] + A * X[I];
end;
```

## The generated code

FPC 3.2.2 `-O3`:

```asm
P$REPRO_$$_AXPY$TVEC$TVEC$DOUBLE:
	movq	$-1,%rax
.Lj5:
	addq	$1,%rax
	movapd	%xmm0,%xmm1
	mulsd	(%rsi,%rax,8),%xmm1
	addsd	(%rdi,%rax,8),%xmm1
	movsd	%xmm1,(%rdi,%rax,8)
	cmpq	$1023,%rax
	jnge	.Lj5
	ret
```

## Expected

Two elements per instruction, as gcc 13 `-O3` emits for `repro.c`, with the scalar loop kept for the one overlap
that would change the result:

```asm
axpy:
	leaq	8(%rsi), %rax
	cmpq	%rax, %rdi
	je	.L5                        # y = x + 1 element: the scalar loop
	unpcklpd	%xmm0, %xmm0
	xorl	%eax, %eax
.L3:
	movupd	(%rsi,%rax), %xmm1
	movupd	(%rdi,%rax), %xmm2
	mulpd	%xmm0, %xmm1
	addpd	%xmm2, %xmm1
	movups	%xmm1, (%rdi,%rax)
	addq	$16, %rax
	cmpq	$8192, %rax
	jne	.L3
	ret
```

## Timings

`./prog` with the default 2,000,000 rounds; median wall time of 5 runs; every program prints `523.776000`.

| program | compiler and options | time |
|---|---|---|
| repro.pas | FPC 3.2.2 `-O3` | 1.58 s |
| repro.pas | FPC 3.2.2 `-O3 -CfAVX2 -CpCOREAVX2` | 1.84 s |
| repro.c | gcc 13.3.0 `-O3` | 0.83 s |
| repro.c | gcc 13.3.0 `-O2` (scalar: no run-time check at -O2) | 2.36 s |
| repro.c with `-DINLINE` | gcc 13.3.0 `-O2` (inlined on the two global arrays: vectorized) | 0.83 s |
| repro.c with `-DINLINE` | gcc 13.3.0 `-O2 -fno-tree-vectorize` | 1.70 s |

The machine had some background load; the times vary by about 10%.

## Possible fixes

A loop vectorizer for counted loops over arrays of floats and integers, with an overlap check of the arrays at run
time, as gcc and clang do. The LLVM back end of FPC may give this already; it was not checked here.
