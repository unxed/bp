# ext/ — extensions of Free Pascal

Layer 2 of 3 in Better Pascal. Not about memory safety but about convenience: what FPC lacks out of the box.

| Part | Files | What it gives |
|---|---|---|
| UTF-8 by default | `utf8.intf.inc`, `utf8.impl.inc`, `utf8.init.inc` | `String` = UTF-8, file names and the console in UTF-8, `CodePoints`, `CPLength`; turned off with `-dSAFE_NO_UTF8` |
| Goroutines | `go.intf.inc`, `go.impl.inc` | `TGroup`/`TTask` (structured concurrency), `TChan<T>`, `Select` (SPEC §14) |
| Threads | `bpthreads.pas` | unit `BPThreads`: a thread manager without libc on Linux (clone/futex/mmap), `cthreads` on the other Unix; empty on DOS |
| UTF-8 for existing code | `fpc-utf8/` | a separate UTF-8-only variant through `-Fa` and a config file, without `BP` ([README](fpc-utf8/README.md)) |

The layer uses the core of `safe/` (`ESafety`, the failure counters); `safe/` knows nothing about it.
Programs get it through `unit BP` (`../bp.pas`), which includes these `.inc` files together with `safe/*.inc`.

Tests: `tests/ext/` (`test_utf8`, `test_go`, `test_threads`, `compile/mf_*`) and `ext/fpc-utf8/test_utf8.pas`;
`tests/run.sh ext` and `tests/run.sh fpc-utf8`.
