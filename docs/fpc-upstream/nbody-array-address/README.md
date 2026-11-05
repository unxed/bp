x86_64: address of A[I] (array of records) recomputed for every field access; not kept in a register across statements

## Summary

In a loop that reads and writes several fields of `B[I]` and `B[J]` (a global
static array of records), FPC computes the element address (`index * SizeOf(record)`,
then base + offset) again for every access: once per statement for each element, and
a second time inside the same statement for the store side of `B[I].F := B[I].F ...`.
The base address of the array is also reloaded before every statement. The index
variables are already in registers and do not change in the loop body.

gcc keeps the two element addresses in registers (and strength-reduces them across
the loop). In the example below FPC emits 24 `imul` in the inner loop body (116
instructions); gcc -O2 emits none (49-53 instructions). Passing the two elements as
`var` parameters gives FPC the expected code.

`-O2`, `-O3`, `-O4`, and `-O3 -OoCSE -OoDFA -OoREGVAR` give the same code.

## Version and options

- FPC 3.2.2 x86_64-linux (`fpc -O3 -al -a repro.pas`). Trunk (3.3.1) was not checked.
- gcc 13.3.0 (`gcc -O2 repro.c -lm`), for comparison.
- CPU: Intel Core i5-6300U.

## Example (repro.pas, abridged)

```pascal
{$mode objfpc}
const
  Dt = Double(0.001);
type
  TBody = record
    X, Y, Z, VX, VY, VZ, M: Double;
  end;
var
  B: array[0..4] of TBody;

procedure Run;
var
  I, J, S: Integer;
  DX, DY, DZ, D2, Mag: Double;
begin
  for S := 1 to 4000000 do
    for I := 0 to 3 do
      for J := I + 1 to 4 do
      begin
        DX := B[I].X - B[J].X;
        DY := B[I].Y - B[J].Y;
        DZ := B[I].Z - B[J].Z;
        D2 := DX * DX + DY * DY + DZ * DZ;
        Mag := Dt / (D2 * Sqrt(D2));
        B[I].VX := B[I].VX - DX * B[J].M * Mag;
        B[I].VY := B[I].VY - DY * B[J].M * Mag;
        B[I].VZ := B[I].VZ - DZ * B[J].M * Mag;
        B[J].VX := B[J].VX + DX * B[I].M * Mag;
        B[J].VY := B[J].VY + DY * B[I].M * Mag;
        B[J].VZ := B[J].VZ + DZ * B[I].M * Mag;
      end;
end;
```

Full files attached: `repro.pas`, `repro_var.pas` (the workaround), `repro.c`.
All three print the same result (`1166.137932 -837.079209`).

## Generated code (FPC 3.2.2 -O3)

I is in `ecx`, J in `esi` (per the `-al` comments). Two consecutive statements:

```
# [22] DX := B[I].X - B[J].X;
	movl	%ecx,%edi
	imulq	$56,%rdi,%r8
	movl	%esi,%edi
	imulq	$56,%rdi,%rdi
	movsd	(%rdx,%r8),%xmm1
	subsd	(%rdx,%rdi),%xmm1
	movapd	%xmm1,%xmm0
	movq	$U_$P$REPRO_$$_B,%rdx
# [23] DY := B[I].Y - B[J].Y;
	movl	%ecx,%edi
	imulq	$56,%rdi,%r8
	movl	%esi,%edi
	imulq	$56,%rdi,%rdi
	movsd	8(%rdx,%r8),%xmm1
	subsd	8(%rdx,%rdi),%xmm1
	movapd	%xmm1,%xmm2
	movq	$U_$P$REPRO_$$_B,%rdx
```

A read-modify-write statement computes `I * 56` twice:

```
# [27] B[I].VX := B[I].VX - DX * B[J].M * Mag;
	movl	%ecx,%edi
	imulq	$56,%rdi,%r8
	movl	%esi,%edi
	imulq	$56,%rdi,%rdi
	movapd	%xmm0,%xmm1
	mulsd	48(%rdx,%rdi),%xmm1
	mulsd	%xmm6,%xmm1
	movsd	24(%rdx,%r8),%xmm4
	subsd	%xmm1,%xmm4
	movl	%ecx,%edi
	imulq	$56,%rdi,%rdi
	movsd	%xmm4,24(%rdx,%rdi)
	movq	$U_$P$REPRO_$$_B,%rdx
```

The same pattern repeats for all 9 statements that touch `B`: 24 `imul` and 8
reloads of the base per inner iteration, 116 instructions in the inner loop.

## Expected code

Compute the two addresses once per iteration of J (or strength-reduce them), and
use them with constant offsets. FPC already produces this for the same body when
the elements come in as `var` parameters (`repro_var.pas`, routine `Pull(var P, Q:
TBody)`, P in `rax`, Q in `rsi`):

```
# DX := P.X - Q.X;
	movsd	(%rax),%xmm0
	subsd	(%rsi),%xmm0
# DY := P.Y - Q.Y;
	movsd	8(%rax),%xmm1
	subsd	8(%rsi),%xmm1
...
# P.VX := P.VX - DX * Q.M * Mag;
	movapd	%xmm0,%xmm4
	mulsd	48(%rsi),%xmm4
	mulsd	%xmm3,%xmm4
	movsd	24(%rax),%xmm5
	subsd	%xmm4,%xmm5
	movsd	%xmm5,24(%rax)
```

(50 instructions for the whole body, no `imul`.) gcc -O2 on `repro.c` keeps
`&b[i]` in `rdx` and `&b[j]` in `rax` (`addq $56, %rax` per iteration of j), with
no multiplication in the loop.

## Timings

Median of 5 runs, user time, the four programs interleaved, i5-6300U (the machine
had some background load, so the numbers vary by about 10%):

| program | time | vs gcc -O2 |
|---|---|---|
| FPC 3.2.2 -O3, `repro.pas` | 0.69 s | 1.97x |
| FPC 3.2.2 -O3, `repro_var.pas` (`var` parameters) | 0.42 s | 1.20x |
| gcc 13.3 -O2, `repro.c` | 0.35 s | 1.00x |
| gcc 13.3 -O2 -fno-tree-vectorize, `repro.c` | 0.40 s | 1.14x |

The `var` variant is faster than the inline loop body even though it adds a call
per pair. In a full n-body program the same change took FPC from 1.91x to 1.36x
of gcc.

## Workaround

Take the element address once: pass the elements as `var` parameters
(`Pull(B[I], B[J])`, `repro_var.pas`), or use pointers in the loop body
(`P := @B[I]; Q := @B[J];` then `P^.X`, `Q^.M`, ...). The pointer form gives
2 `imul` per iteration of J instead of 24 and runs in 0.42 s, the same as the
`var` form.
