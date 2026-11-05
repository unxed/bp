#!/usr/bin/env bash
# The build time of a project of many files, Better Pascal against C, Go, Rust and Goose (safe/SPEC.md §25.5; report
# only, no thresholds): the same program of MODULES modules of FUNCS functions in each language
# (tests/bench/suite/project/gen.py), a clean build and a rebuild after an edit of one file (the body of a function of
# the last module, which only the main program calls). Beside hello world in tests/bench/size.sh: a small program
# shows the fixed cost of a build, a project shows what a build system does with the files that did not change.
# Variants:  bp: tools/bp build --release -O2            bp-debug: tools/bp build (-Cr -Co, the edit loop)
#            gcc: make -j$(nproc) with CFLAGS=-O2, a .c and a .h per module, the headers of the C library included
#            go: go build (a package per module)
#            rust: cargo build --release (one crate, a module per file)   rust-dev: cargo build (incremental)
#            goose: goose build -O2 (the whole program from the root file)
# A clean build: the project written anew (another value in the edited function, so no cache of a check or of a
# compiler holds it), the object directory, the Go build cache, the target of cargo and GOOSE_HOME made anew; median
# of 3. A rebuild: the source of the last module written again with another value, nothing else; median of 5. Each
# binary must print what gen.py prints.
# usage: tests/bench/project.sh [out-dir]
# environment: MODULES (20)   FUNCS (40)   VARIANTS (all of the above)   FPC (fpc)   GOOSE (as in size.sh)
set -u
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-$(mktemp -d)}
MODULES=${MODULES:-20}
FUNCS=${FUNCS:-40}
VARIANTS=${VARIANTS:-"bp bp-debug gcc go rust rust-dev goose"}
FPC=${FPC:-fpc}
if [ -z "${GOOSE:-}" ]; then
  if command -v goose > /dev/null 2>&1; then GOOSE=goose; else GOOSE=$HOME/.local/opt/goose-v2026.3/goose; fi
fi
mkdir -p "$out"
out=$(cd "$out" && pwd)
jobs=$(nproc 2> /dev/null || echo 1)
failed=0
salt=0

have() { command -v "$1" > /dev/null 2>&1; }

avail() {
  case $1 in
    bp | bp-debug) have "$FPC" && have python3 ;;
    gcc) have gcc && have make ;;
    go) have go ;;
    rust | rust-dev) have cargo ;;
    goose) have "$GOOSE" && have gcc ;;
    *) return 1 ;;
  esac
}

lang() { case $1 in bp*) echo bp ;; gcc) echo c ;; rust*) echo rust ;; *) echo "$1" ;; esac; }

# gen VARIANT [edit]: writes the project of the variant (all of it, or only the edited file) with a new value;
# $want is what the program must print
gen() {
  salt=$((salt + 1))
  local a=(--modules "$MODULES" --funcs "$FUNCS" --langs "$(lang "$1")")
  [ "${2:-}" != edit ] || a+=(--edit "$salt")
  [ "${2:-}" = edit ] || a+=(--salt "$salt")
  want=$(python3 -I "$here/suite/project/gen.py" "$out/$1" "${a[@]}")
}

# build VARIANT [clean]: the binary is $out/VARIANT.bin
build() {
  local v=$1 d=$out/$1 o=$out/obj-$1
  [ "${2:-}" != clean ] || { rm -rf "${o:?}" && mkdir -p "$o"; }
  case $v in
    bp) "$root/tools/bp" build --release -O2 -FU"$o" -FE"$o" "$d/bp/main.pas" && cp "$o/main" "$d.bin" ;;
    bp-debug) "$root/tools/bp" build -FU"$o" -FE"$o" "$d/bp/main.pas" && cp "$o/main" "$d.bin" ;;
    gcc) make -s -j"$jobs" -C "$d/c" CFLAGS=-O2 && cp "$d/c/main" "$d.bin" ;;
    go) (cd "$d/go" && GOCACHE=$o/gocache go build -o "$d.bin" .) ;;
    rust) [ "${2:-}" != clean ] || rm -rf "${d:?}/rust/target"
          (cd "$d/rust" && cargo build --release -q --offline) && cp "$d/rust/target/release/proj" "$d.bin" ;;
    rust-dev) [ "${2:-}" != clean ] || rm -rf "${d:?}/rust/target"
              (cd "$d/rust" && cargo build -q --offline) && cp "$d/rust/target/debug/proj" "$d.bin" ;;
    goose) GOOSE_HOME=$o/goosehome GOOSE_CC=gcc "$GOOSE" build -O2 -o "$d.bin" "$d/goose/main.goose" ;;
  esac
}

now_us() { local t=$EPOCHREALTIME; echo "${t/./}"; }
med() { sort -n | sed -n "$((($1 + 1) / 2))p"; }
ms() { printf '%d' $(($1 / 1000)); }

declare -A btime rtime note
for v in $VARIANTS; do
  if ! avail "$v"; then note[$v]="not available"; continue; fi
  echo "== $v" >&2
  ts=() rs=()
  for i in 1 2 3; do
    rm -rf "${out:?}/$v"
    gen "$v"
    t0=$(now_us)
    build "$v" clean > "$out/build-$v.log" 2>&1 || { echo "build of $v failed; see $out/build-$v.log" >&2; failed=1; break; }
    t1=$(now_us)
    ts+=($((t1 - t0)))
    [ "$("$out/$v.bin")" = "$want" ] || { echo "$v printed another value" >&2; failed=1; ts=(); break; }
  done
  [ ${#ts[@]} = 3 ] || { note[$v]=failed; continue; }
  for i in 1 2 3 4 5; do
    # not timed: fpc compares the time of a source with the one in its .ppu to the second, so an edit within the
    # second of the last build, at the same size, would not be compiled
    sleep 1
    gen "$v" edit
    t0=$(now_us)
    build "$v" > "$out/rebuild-$v.log" 2>&1 || { echo "rebuild of $v failed; see $out/rebuild-$v.log" >&2; failed=1; break; }
    t1=$(now_us)
    rs+=($((t1 - t0)))
    [ "$("$out/$v.bin")" = "$want" ] || { echo "$v printed another value after an edit" >&2; failed=1; rs=(); break; }
  done
  [ ${#rs[@]} = 5 ] || { note[$v]=failed; continue; }
  btime[$v]=$(printf '%s\n' "${ts[@]}" | med 3)
  rtime[$v]=$(printf '%s\n' "${rs[@]}" | med 5)
done

cpu=$(grep -m1 'model name' /proc/cpuinfo 2> /dev/null | sed 's/^[^:]*: *//')
echo
echo "Machine: ${cpu:-unknown CPU}, $jobs logical CPUs, $(uname -sr)"
echo
echo "Compilers: fpc $("$FPC" -iV 2> /dev/null); $(gcc --version 2> /dev/null | head -n 1); $(cargo --version 2> /dev/null);" \
  "$(go version 2> /dev/null); goose $("$GOOSE" version 2> /dev/null | head -n 1)"
echo
echo "A project of $MODULES modules of $FUNCS functions ($(cat "$out"/bp*/bp/*.pas 2> /dev/null | wc -l) lines of Pascal):" \
  "a clean build (median of 3) and a rebuild after an edit of one file (median of 5)."
echo
echo "| variant | clean build | rebuild after an edit |"
echo "|---|---|---|"
for v in $VARIANTS; do
  if [ -z "${rtime[$v]:-}" ]; then echo "| $v | ${note[$v]:-failed} | |"; continue; fi
  echo "| $v | $(ms "${btime[$v]}") ms | $(ms "${rtime[$v]}") ms |"
done
exit $failed
