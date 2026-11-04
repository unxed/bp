# httpd: an HTTP/1.1 server on goroutines

`httpd.pas` is one program file of 300 lines in the bp dialect. It shows:

- **The build.** `tools/bp build` checks it (`bpvet --strict --typed`: ownership, regions, borrows) and compiles it to one
  static file without libc. The only mark is the one every program carries on its `uses` line (`BP` goes first).
- **Goroutines** (`safe/SPEC.md` §14): a `TGroup`, one acceptor task, a pool of worker tasks that take accepted sockets
  from a `TChan<TSocket>`. SIGTERM or SIGINT shut the listening socket down; the acceptor tells the main thread, which
  cancels the group and waits for it, and `SafeCheckNoLeaks` prints `no leaks`.
- **Three memory styles in one program** (§20): values (strings, records), owners (`TOwned` of the socket stream and of
  the server), and regions (the parsed request and its headers).
- **HTTP/1.1**: the request line and the headers, bodies by `Content-Length`, keep-alive (the default of HTTP/1.1, and
  HTTP/1.0 with `Connection: keep-alive`), `Connection: close`, 400 on garbage (and on `Transfer-Encoding`, which it does
  not support), 404 on an unknown path. Routes: `/` (text), `/json?n=NUM` (NUM squares, 0..1000, default 10), `/stats`
  (requests served and bytes of response bodies).
- **FPC packages as they are**: `Sockets` of the RTL (system calls, no libc) and `ssockets` of fcl-net (bind and the socket
  streams) are used as unchecked units, as a C library is used from Rust.

## Build and run

```sh
tools/bp build -Futools/spikes/region -FEout examples/httpd/httpd.pas   # --release drops -Cr -Co
out/httpd 8080 &                                                        # httpd [PORT [WORKERS]], default 8080 and 64
curl localhost:8080/; curl 'localhost:8080/json?n=5'; curl localhost:8080/stats
kill -TERM %1                                                           # prints the counters and "no leaks"
```

The region style is the spike unit `tools/spikes/region` (§20, spike 2), hence `-Futools/spikes/region`.
`tests/examples.sh` (CI, job `lint`) builds it, checks that it is static, sends the requests above, a garbage request,
a body and a pipelined request, then SIGTERM, and expects `no leaks` and exit code 0.

## The design against the specification

| In `httpd.pas` | `safe/SPEC.md` |
|---|---|
| `G.Go(TAcceptor.Create(Listener, Conns, Quit))`, `G.Go(TWorker.Create(Conns))`: a task is a class, its data are fields set in the constructor (a socket number, channels) | §14, S11 |
| `TConns = specialize TChan<TSocket>`: accepted sockets go to the pool by value; a worker waits with `Select([FConns.Sel, Done], 1000)` | §14 |
| `Quit.Recv(V); Server.Reset; G.Cancel; G.Wait`: the group waits for every task; a worker sees `Done` or `Cancelled` | §14 (structured concurrency) |
| `InterlockedIncrement64(Requests)`: two global counters, as in `tests/ext/test_go.pas`; a global shared by goroutines is not checked yet | §0, §21.2 |
| `TStreamBox.Own(TSocketStream.Create(Fd))`: one owner closes the socket when `Serve` returns | §0 (2), §4 |
| `R := TRegion.Create; while Exchange(...) do R.Reset`: a region per connection, reset after each request | §20 (region style; "a loop uses `Reset`") |
| `TRequest = class(TRegionObject)` with `THeaders = specialize TGrowArray<THeader>`, made by `TryParse`, which declares no region: they are allocated in the region of its caller | §20 (the current region, rule 4) |
| The target, the header values and the JSON are `String`: counted copies, safe outside the region | §20 (strings) |
| `SafeCheckNoLeaks` at the end | §5, §22.3 (R5) |

## Findings

- **Regions are used and accepted.** `tools/bp build -Futools/spikes/region` passes the program without a finding and
  without a mark: S17 roots the request in the region of `Serve` and finds no use after `Reset`.
- **A region per request was twice as slow after the first load; a region per connection is not.** With
  `TRegion.Create` inside the exchange, each request took the first block (4 KiB) from the FPC heap and gave it back, and
  from the second load on the heap mapped and unmapped memory for it on every request (the threads waited in
  `mmap`/`munmap`; on 4 cores, 16k against 33k requests per second on `/`). One region per connection with `Reset` keeps
  its block, as §20 says of loops, and the throughput stays.
- **`Select` without a timeout overflows in a debug build.** `ext/go.impl.inc` computes `GetTickCount64 + QWord(TimeoutMs)`
  with `TimeoutMs = -1`; `-Co`, which every `bp build` without `--release` adds, raises `EIntOverflow` in the task. The
  tests build without `-Co`, so they do not see it. The example passes a timeout of one second and loops; `ext/` is
  unchanged here.
- **The RTL stubs of bpvet drop calling conventions.** `signalhandler_t` has no `cdecl` in them, so a `cdecl` handler does
  not resolve; the handler gets `cdecl` from `{$calling cdecl}`, which the resolver does not read.
- **The resolver is stricter than FPC in three places:** `Pos(#13#10, S)` is ambiguous (an untyped constant of two
  characters also matches the `Char` overload), `Delete` of a `String` does not resolve, and `S[1]` is not accepted as an
  untyped `var` argument. The program uses typed constants, `Copy` and a byte buffer instead.
- **Binding needs an address.** `fpBind` and `fpsetsockopt` of `Sockets` take a pointer (`@`, S4); the listening socket
  comes from `TInetServer` of fcl-net instead, so no mark is needed.
- **The pool is sized by connections, not by CPUs.** One task is one OS thread, and a worker keeps its keep-alive
  connection between requests (as a thread of Apache does), so 64 workers serve 64 keep-alive clients at once and a 65th
  waits in the channel until a worker is free (an idle connection is closed after 2 seconds). Goroutines M:N (§21.3)
  would lift this. (`GetCPUCount` of FPC 3.2.2 returns 1 on Linux.)

## Benchmark

`bench/run.sh` builds the three servers (`tools/bp build --release`; `go build`; `rustc -O -C target-cpu=native`), runs
each on a port of its own under `/usr/bin/time -v`, warms it up, and loads `/`, `/json?n=100` and `/stats` with
`ab -k -c 64 -n 100000` (`wrk` when it is on PATH). `bench/main.go` is the same server on `net/http`; `bench/main.rs` uses
the standard library only, a thread per connection and the same minimal HTTP handling, so the comparison is of the
runtimes and threads, not of HTTP libraries. CI runs it in the job `bench-httpd` (report only).

Measured 2026-11-04 by CI (run 41926782782, job `bench-httpd`) on `ubuntu-latest`, 4 vCPU: FPC 3.2.2, Go 1.24.13,
rustc 1.99.1; `ab -k -c 64 -n 100000`. Peak RSS is of the whole run of a server (warm-up and three loads).

| Server | Route | Requests/s | Mean latency, ms | Binary, bytes | Peak RSS, KiB |
|---|---|---|---|---|---|
| bp | `/` | 63917 | 1.00 | 1637312 | 31756 |
| bp | `/json?n=100` | 63833 | 1.00 | 1637312 | 31756 |
| bp | `/stats` | 63526 | 1.01 | 1637312 | 31756 |
| Go | `/` | 74685 | 0.86 | 8248208 | 14780 |
| Go | `/json?n=100` | 74251 | 0.86 | 8248208 | 14780 |
| Go | `/stats` | 74684 | 0.86 | 8248208 | 14780 |
| Rust | `/` | 63758 | 1.00 | 4619176 | 4304 |
| Rust | `/json?n=100` | 62535 | 1.02 | 4619176 | 4304 |
| Rust | `/stats` | 63049 | 1.01 | 4619176 | 4304 |

It shows that the server of bp, with a thread per keep-alive connection, a region per connection and the FPC code
generator, serves as many small requests as the same design in Rust and within 15 % of Go, from a static binary of a
fifth of the size of Go's, at about twice Go's memory (64 worker threads with heaps and stacks of their own). It does
not show which server is faster: `ab` runs on one thread on the same 4 vCPU and is close to its own limit, the runner is
shared, and 64 connections on one machine say nothing of thousands (where one OS thread per task is the limit of §14).
