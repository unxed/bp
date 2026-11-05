x86_64: a record parameter passed in registers is stored to the stack on entry and read back on every use

## Summary

A `const` record of 16 bytes (a dynamic array and a `Cardinal`) is passed in two registers (`%rdi`, `%rsi`). The
callee stores both to its frame at once and then reads the array pointer back from the stack before every use, and
both halves again before each call that passes the record on. Two callee-saved registers (`%r14`, `%r15`) stay free,
so the record could live in registers for the whole routine, as gcc keeps a struct passed by value.

In a recursive walk of a tree stored in an array (the arena variant of the binary-trees benchmark) this costs about
35%: 0.23 s against 0.17 s when the record is passed by reference (`constref`), and gcc takes 0.14 s for the same
code with its interprocedural tricks off.

Found in the benchmarks of Better Pascal (https://github.com/unxed/bp), a safe dialect of Object Pascal that builds
with stock FPC: the arena tier of binary trees runs at 1.6x of gcc there, and this is one of the causes.

## Versions and options

- FPC 3.2.2 (Ubuntu 3.2.2+dfsg-32, x86_64-linux) and main at d7965e4b, 3.3.1 [2026/11/05], x86_64-linux: the same
  code.
- `fpc -O3 -al repro.pas`; `-O2` and `-O4` give the same routine.
- Reference: gcc 13.3.0 on `repro.c`, the same program with the struct passed by value.
- Intel Core i5-6300U, Linux 6.8.0.

## The program

`repro.pas` (attached; `repro_ref.pas` is the same with `constref A`; `repro.c` the same in C):

```pascal
type
  TNode = record
    Left, Right: Cardinal;
  end;
  TPool = record          { 16 bytes: passed in two registers by value }
    Items: array of TNode;
    Len: Cardinal;
  end;

function Check(const A: TPool; const T: Cardinal): Int64;
begin
  Result := 1;
  if A.Items[T].Left <> None then
    Result := Result + Check(A, A.Items[T].Left) + Check(A, A.Items[T].Right);
end;
```

## The generated code

FPC 3.2.2 and main, `-O3`:

```asm
P$REPRO_$$_CHECK$TPOOL$LONGWORD$$INT64:
	pushq	%rbx
	pushq	%r12
	pushq	%r13
	leaq	-16(%rsp),%rsp
	movq	%rdi,(%rsp)                # the record goes to the stack
	movq	%rsi,8(%rsp)
	movl	%edx,%ebx
	movl	$1,%r12d
	movq	(%rsp),%rdx                # A.Items read back
	movl	%ebx,%eax
	cmpl	$4294967295,(%rdx,%rax,8)
	je	.Lj10
	movq	(%rsp),%rdx                # read back again
	movl	%ebx,%eax
	movl	(%rdx,%rax,8),%edx
	movq	(%rsp),%rdi                # both halves read back for the call
	movq	8(%rsp),%rsi
	call	P$REPRO_$$_CHECK$TPOOL$LONGWORD$$INT64
	leaq	(%r12,%rax),%r13
	movq	(%rsp),%rax                # read back again
	andl	%ebx,%ebx
	movl	4(%rax,%rbx,8),%edx
	movq	(%rsp),%rdi                # and again for the call
	movq	8(%rsp),%rsi
	call	P$REPRO_$$_CHECK$TPOOL$LONGWORD$$INT64
	...
```

## Expected

The halves kept in callee-saved registers, as gcc 13 does for the struct of `repro.c` (here with
`-O2 -fno-inline -fno-ipa-sra -fno-optimize-sibling-calls`, so that it keeps the same calls):

```asm
check:
	pushq	%r13
	...
	movq	%rdi, %r12                 # the struct stays in %r12:%r13
	movq	%rsi, %r13
	...
	movq	%r12, %rdi
	movq	%r13, %rsi
	call	check
```

## Timings

`./prog` with the default 400 rounds over a tree of 131071 nodes; median wall time of 5 runs; every program prints
`52428400`.

| program | compiler and options | time |
|---|---|---|
| repro.pas (`const A: TPool`) | FPC 3.2.2 `-O3` | 0.23 s |
| repro_ref.pas (`constref A: TPool`) | FPC 3.2.2 `-O3` | 0.17 s |
| repro.c | gcc 13.3.0 `-O2 -fno-inline -fno-ipa-sra -fno-optimize-sibling-calls` | 0.14 s |
| repro.c | gcc 13.3.0 `-O2` (inlines the recursion into itself) | 0.10 s |

## Possible fixes

Workaround: pass the record by reference (`constref` or `var`), or pass its fields as separate parameters.

A fix could keep a record parameter that arrives in registers in (callee-saved) registers when its address is not
taken, and read its fields from there.
