# fpide: Text Mode IDE on tv3

The **Free Pascal Text Mode IDE** moved from **Free Vision** (`packages/fv`) onto **[unxed/tv3](https://github.com/unxed/tv3)**:
UTF-8 inside, a model of **classes** instead of `object`/`New`/`Dispose`, the same build targets as DN (Linux x86_64 first).

The parts: the submodule `fpide/tv/` → tv3, shims, CI, acceptance tests that click through the UI.

| Directory | Purpose |
|---|---|
| [`fpide/src/`](src/) | the IDE sources (base: FPC `packages/ide` @ 3.2.2) |
| [`fpide/bootstrap/`](bootstrap/) | the FPC pin + fetching the `compiler/` sources, only for `FPIDE_EMBED=1` |
| [`fpide/compat/fpc/`](compat/fpc/) | a few units of the FPC 3.2.2 compiler (`globtype`, `systems`, `tokens`, …) that the IDE needs even without the built-in compiler |
| [`compat/shims/`](compat/shims/) | the map of Free Vision names → tv3 (`tools/gen-shim.py`) |
| [`tv/`](tv/) | git submodule tv3 (a separate licence; its code is not mixed with `fpide/`) |
| [`tools/build-fpide.sh`](tools/build-fpide.sh) | the build (the heavy parts need not run locally, see CI) |

Plan and milestones: [`PLAN.md`](PLAN.md). Current status: [`MIGRATION-STATUS.md`](MIGRATION-STATUS.md).

## Local preflight (before a push)

Before a push: `fpide/tools/fpide-setup-build.sh test` (build ~15 s, tests ~2 min side by side, each section of `test_functions.py` and 8 copies of the IDE for the sweep: `test_accept.py`, `test_config.py`, `test_functions.py` (clicks through the main functions, the debugger included), `test_menu_sweep.py` (`-j N`, `--part K/N`)).
The build log must have no `An inherited method is hidden by ...` warnings (a lost `override`).

## Build

Only Ubuntu/Debian with `apt` and git are needed. One command (installs the packages, fetches `fpide/tv/`, builds; with `test` it also runs the tests):

```sh
git clone --recurse-submodules https://github.com/unxed/bp && cd bp
fpide/tools/fpide-setup-build.sh [test]     # result: fpide/out/linux64/fp
```

Or by hand, if `fpc` (3.2.x), `gdb` and `tmux` are installed: `git submodule update --init fpide/tv && fpide/tools/build-fpide.sh`.
The target is taken from the current system (now `linux64`); the `fpc` from PATH is used (`FPC=/path/to/fpc` for another one).

**The compiler and the debugger are external.** The IDE runs `fpc` and `gdb` of the system (like the other tools); the compiler is
found in PATH automatically. Another one: the variable `FP_COMPILER=/path/to/fpc` or the line `Compiler=` in the `[Compile]` section of
`fp.ini` (`auto` by default, a path, or `builtin` for a build with the built-in compiler). The few compiler units that the IDE itself
must know (`globtype`, `systems`, `tokens`, `comphook`, …) are in `fpide/compat/fpc/`, in the repository; nothing is downloaded.
An external compiler gives no information for the symbol browser (Search > Objects/Modules/Globals/Symbol), so the browser is built
from the sources: the program (or unit) and the used units found next to it are parsed by the FCL parser (`fcl-passrc`,
`fpide/src/fpsrcbrw.pas`): declarations, classes with their ancestors, members, procedures with parameters. The sources are read
from disk each time the browser opens.

`FPIDE_EMBED=1 fpide/tools/build-fpide.sh` builds with the built-in FPC compiler (downloads the `compiler/` sources of FPC 3.2.2,
~400 MB; result: `fpide/out/linux64-embed/fp`).

Variables: `FPIDE_TV=/path/to/tv3`, `FPIDE_GDBMI=1` (the default), `FPIDE_NOGDB=1` (no debugger), `FPIDE_EXTRA` (extra FPC flags).

## Where the files are

The settings of the user (`fp.ini`, `fp.cfg`) are in the configuration directory of the system, the desktop (`fp.dsk`) in its
state directory (unit `TvAppDir` of tv3):

| system | `fp.ini`, `fp.cfg` | `fp.dsk` |
|---|---|---|
| Linux, BSD | `$XDG_CONFIG_HOME/fp` (`~/.config/fp`) | `$XDG_STATE_HOME/fp` (`~/.local/state/fp`) |
| macOS | `~/Library/Application Support/fp` | the same |
| Windows | `%APPDATA%\fp` | `%LOCALAPPDATA%\fp` |
| DOS, OS/2 | the directory of the program | the same |

On the first start (no `fp.ini` there yet) `fp.ini`, `fp.cfg`, `fp.dsk` and `fp.dir` are copied from `~/.fp` (Unix) or from the
directory of the program (Windows); the old files are left in place. A project directory keeps its own `fp.ini`, `fp.cfg`,
`fp.dsk` and `fp.dir` as before (once the user has an `fp.ini`, the IDE asks whether to make them when it starts in a directory without `fp.dir`; the first
start, which asks nothing, leaves an `fp.dir` in its directory). The shared
files (templates `*.pt`, tools `*.tdf`, a system-wide `fp.ini`) are looked up in `lib/fpc/<version>/ide/text` next to the
program, else in the directory of the program; `fp.ini` is never written there.

## Acceptance

The screen must match the vanilla IDE after the same actions: **text, colour, background** (and the other screen attributes), bit
for bit, except for the difference of encodings (vanilla CP866/OEM vs UTF-8 here). The workflow `.github/workflows/fpide-accept.yml`
(still in progress).
