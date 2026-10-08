# fpide: Text Mode IDE on Free Pascal + tv3

Goal: the **Text Mode IDE** of the FPC distribution (`packages/ide`) built on **[unxed/tv3](https://github.com/unxed/tv3)** instead of **Free Vision**, with **UTF-8** and the move **`object` → `class`**, with behaviour on screen that cannot be told from the vanilla IDE (once the encodings are accounted for).

**Priority:** move everything over **without breaking any function**. Stubbing out the compiler, the debugger, the editor or the help just to link, or narrowing the product to "UI only", is not allowed. **Decision of the owner (2026-10-06):** the compiler and the debugger are **external programs** of the system (`fpc`, `gdb`) that the IDE runs itself; the built-in FPC compiler stays an option (`FPIDE_EMBED=1`). The build is one command on Ubuntu (`tools/fpide-setup-build.sh`), without downloading the FPC sources.

How we work (as in `unxed/dn`): commits to **`main`**, the heavy build and the tests run in **GitHub Actions**, the submodule `tv/` points to tv3. Before a push: the local `tools/fpide-preflight.sh`.

## Sources

| What | Where |
|---|---|
| IDE | FPC `packages/ide`, tag `release_3_2_2`: [`fpide/bootstrap/upstream.env`](bootstrap/upstream.env) |
| Compiler | the system `fpc` (external); the few compiler units that the IDE itself needs are in [`compat/fpc`](compat/fpc). The built-in variant (`FPIDE_EMBED=1`): the `compiler/` tree of the same FPC tag |
| UI (in place of FV) | [unxed/tv3](https://github.com/unxed/tv3), submodule `tv/` |
| Reference of behaviour | the IDE binary of the same FPC 3.2.x (`fp` / `fpide`) on Linux, compared by screen dumps |

Free Vision is **not** copied into the repository: the FV unit names (`Views`, `App`, …) are provided by **shim units** generated from tv3 (`tools/gen-shim.py`, map `fpide/compat/shims/shims.map`).

Compiling from the IDE goes through the external `fpc` (the output is parsed, errors can be jumped to, messages are listed); debugging goes through `gdb` (GDB/MI), and the debugged program has its own pty. The symbol browser is built from the sources by the FCL parser (`fpsrcbrw.pas`).

## Decisions

1. **Two independent trees:** `tv/` knows nothing of `fpide/`; `fpide/` uses tv3 only as a package. Checked by `tools/check-fpide-layout.sh`.
2. **The IDE base is the public FPC 3.2.2**, reproducible with `fpide/bootstrap/run.sh`; after that, ordinary commits to `fpide/src`.
3. **The compiler is the external `fpc`** (found automatically; `FP_COMPILER`/`fp.ini` for another one). The built-in FPC `compiler/` is only for `FPIDE_EMBED=1`; it is not committed (pin in `upstream.env`, `fpide/bootstrap/ensure-compiler.sh`).
4. **UTF-8** as in tv3/DN: the sources, strings and resources of the IDE are UTF-8; the editor opens, edits and saves UTF-8 (a column is a character, wide characters take two cells); the single-byte mode is only for DOS.
5. **Classes** follow the same plan as DN (`CLASS-MIGRATION.md` in dn): aliases, fields, `New`/`Done`, then the resources and the editor units.
6. **Debugger** as in the upstream FPC IDE on Linux: **GDB/MI** by default (`-dGDBMI`). `FPIDE_NOGDB=1` only as an explicit override, not a goal of the port.
7. **CI** on `ubuntu-24.04`: build and acceptance (`fpide-accept.yml`: `test_accept.py`, `test_functions.py`, `test_menu_sweep.py`); locally `tools/fpide-setup-build.sh test`.

## Milestones

| # | Content | Done when |
|---|---|---|
| 0 | Repository skeleton, submodule tv3, CI | done |
| 1 | Shims FV→tv3; `fp.pas` links (linux64, GDB/MI, external fpc/gdb) | done |
| 2 | Start-up: menu, status line, exit | done (`test_accept.py`, `test_functions.py`) |
| 3 | Editor (UTF-8), open/save dialogs, clipboard, mouse | done |
| 4 | Compiling from the IDE (external fpc), messages, running, debugger (gdb), symbol browser | done; help: the CHM files are not shipped (as upstream) |
| 5 | Class migration | done for fpide |
| 6 | Full acceptance (all menu items, hot keys) | the menu items pass `test_menu_sweep.py`, the functions `test_functions.py`; the bit-for-bit comparison with the vanilla IDE is open |

## Open

- The exact shim map for the IDE units (`WEditor`, `Tabs`, …): partly FV, partly IDE only.
- The IDE help (CHM) and the help viewer (`whlpview`, counting in bytes).
- Better Pascal alongside (`bp.pas`, `safe/`, `ext/` at the root of the repository) does **not** block fpide; integration may come later.

## Other languages (stage 7)

Done: `src/fplang.pas`, a class that is the backend of a language (tool, arguments, output parsing, debugger); **Go** comes first: Compile (go vet),
Make/Build (`go build`, in a module the package of the file is built), Run (runs what was built), Compile > Test (`go test`); errors with a position
go to the Compiler Messages window, Enter jumps to the line. Unit test `tests/unit/t_fplang.pas`, acceptance `test_functions.py <fp> golang`.
Highlighting of `.go`: the grammar `lang-go.hl` of tve.

Done: the template of a new Go file (File > Open of a `.go` that does not exist: `NewFileText`), Tools > Format Go file (`gofmt -w`, silent reload `ReloadSilently`).
Done (first slice): the Go debugger is Delve. `src/fpdlv.pas` is a DAP client for `dlv dap` (TCP on localhost, mode `debug`: dlv builds the program itself with `-N -l`),
`src/fpgodbg.pas` ties it to the Run menu: Run with a breakpoint in a `.go` file (or F7/F8 without a session: stop in `main.main`), F8 step over, F7 trace into,
Alt+F4 step out, F4 run to cursor, Continue, Program reset; the breakpoints of the IDE list (Ctrl+F8) are passed to dlv before each run; the line where the program stopped
is highlighted as the debugger row; at the end a window shows the exit code and the last lines of the program output. Unit test `tests/unit/t_fpdlv.pas`
(the real dlv; skipped without dlv/go), acceptance `test_functions.py <fp> debuggo`.
Done for Go since: the Watches, Evaluate (Ctrl+F4) and Call stack windows are served by Delve while a session is open (hooks `ForeignEval`,
`ForeignFrame*` in `fpdebug.pas`; the expression `$locals` lists the arguments and local variables; choosing a frame in the Call stack window evaluates in it);
the condition and the ignore count of a breakpoint go to dlv (`condition` and `hitCondition` "> N" of `setBreakpoints`); the output of the running program is
listed live in the Messages window and the keyboard goes to its standard input (the status line shows the line, Enter sends it, Esc interrupts the program).
Not done for Go: the Registers, FPU, vector and Disassembly windows (dlv has no DAP request for them), expressions with function calls (Delve refuses them),
breakpoints on a function name or a watchpoint from the IDE list. Delve was checked with 1.25.2 and Go 1.24 (dlv 1.27 needs a newer Go); build errors of the program go to the Compiler Messages window.
Other languages were not part of the task: the class `TLangBackend` is ready, but no new languages are added without a separate request.
