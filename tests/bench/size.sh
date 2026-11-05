#!/usr/bin/env bash
# The size of a binary, its memory, its start and the build time of the smallest program, Better Pascal against C, Rust,
# Go and Goose (safe/SPEC.md §25.5; report only, no thresholds). The program prints one line
# (tests/bench/suite/hello/hello.{pas,c,rs,go,goose}); hello_sysutils.pas adds SysUtils and Format.
# Variants:  bp: tools/bp build --release -O2 (with -XX -CX, smart linking)   bp-sysutils: the same, hello_sysutils.pas
#            bp-libc: the same as bp with -dSAFE_LIBC (dynamic, glibc: the mode of an FFI to C, SPEC §18)
#            gcc: gcc -O2 (dynamic, glibc)            gcc-static: gcc -O2 -static
#            rust: rustc -O (dynamic, glibc)          rust-static: rustc -O -C target-feature=+crt-static (static glibc)
#            rust-musl: rustc -O --target x86_64-unknown-linux-musl (n/a when the target is not installed)
#                                                     rust-small: rustc -C opt-level=z -C panic=abort -C lto
#                                                       -C codegen-units=1 -C strip=symbols
#            go: go build (static)                    go-small: go build -ldflags="-s -w"
#            go-dyn: CGO_ENABLED=1 go build -ldflags=-linkmode=external (dynamic, glibc)
#            goose: goose build -O2 (over gcc; dynamic, glibc)
#            goose-static: the same with gcc -static (a wrapper given as GOOSE_CC)
# Like for like (SPEC §25.5): static is compared with static (bp, gcc-static, rust-static, go, goose-static) and dynamic
# with dynamic (bp-libc, gcc, rust, go-dyn, goose).
# Columns: the build time (a clean build, the median of 3; the build caches of Go and Rust stay, as a user has them), a
# rebuild after an edit (a comment line added to the source) with the object directory kept (the units of BP built,
# as for the next build of a program; median of 3),
# the size as built and stripped (strip --strip-all of a copy), static or dynamic, the peak RSS (/usr/bin/time, the
# median of 5) and the start: the mean wall time of one run of N (tests/bench/spawn.c).
# usage: tests/bench/size.sh [out-dir]
# environment: N (1000)   VARIANTS (all of the above)   FPC (fpc)   GOOSE (as in compare.sh)
set -u
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-$(mktemp -d)}
N=${N:-1000}
VARIANTS=${VARIANTS:-"bp bp-sysutils bp-libc gcc gcc-static rust rust-static rust-musl rust-small go go-dyn go-small goose goose-static"}
FPC=${FPC:-fpc}
if [ -z "${GOOSE:-}" ]; then
  if command -v goose > /dev/null 2>&1; then GOOSE=goose; else GOOSE=$HOME/.local/opt/goose-v2026.3/goose; fi
fi
mkdir -p "$out"
failed=0
# the C compiler of goose-static: gcc with -static (an absolute path, as goose runs it from another directory)
gccstatic=$(cd "$out" && pwd)/wrap-gcc-static.sh
printf '#!/bin/sh\nexec gcc "$@" -static\n' > "$gccstatic" && chmod +x "$gccstatic"
# a copy of the sources: a rebuild edits it
src=$out/src
rm -rf "${src:?}" && cp -r "$here/suite/hello" "$src"

have() { command -v "$1" > /dev/null 2>&1; }

avail() {
  case $1 in
    bp | bp-sysutils | bp-libc) have "$FPC" && have python3 ;;
    gcc | gcc-static) have gcc ;;
    rust | rust-static | rust-small) have rustc ;;
    rust-musl) have rustc && [ -d "$(rustc --print target-libdir --target x86_64-unknown-linux-musl 2> /dev/null)" ] ;;
    go | go-small) have go ;;
    go-dyn) have go && have gcc ;;
    goose | goose-static) have "$GOOSE" && have gcc ;;
    *) return 1 ;;
  esac
}

# build VARIANT [keep]: the binary is $out/VARIANT; the object directory is made anew unless keep
build() {
  local v=$1 b=$out/$1 o=$out/obj-$1
  [ "${2:-}" = keep ] || { rm -rf "${o:?}" && mkdir -p "$o"; }
  case $v in
    bp) "$root/tools/bp" build --release -O2 -FU"$o" -FE"$o" "$src/hello.pas" && mv "$o/hello" "$b" ;;
    bp-libc) "$root/tools/bp" build --release -O2 -dSAFE_LIBC -FU"$o" -FE"$o" "$src/hello.pas" && mv "$o/hello" "$b" ;;
    bp-sysutils) "$root/tools/bp" build --release -O2 -FU"$o" -FE"$o" "$src/hello_sysutils.pas" \
      && mv "$o/hello_sysutils" "$b" ;;
    gcc) gcc -O2 -o "$b" "$src/hello.c" ;;
    gcc-static) gcc -O2 -static -o "$b" "$src/hello.c" ;;
    rust) rustc -O -o "$b" "$src/hello.rs" ;;
    rust-static) rustc -O -C target-feature=+crt-static -o "$b" "$src/hello.rs" ;;
    rust-musl) rustc -O --target x86_64-unknown-linux-musl -o "$b" "$src/hello.rs" ;;
    rust-small) rustc -C opt-level=z -C panic=abort -C lto -C codegen-units=1 -C strip=symbols -o "$b" "$src/hello.rs" ;;
    go) (cd "$o" && go build -o "$b" "$src/hello.go") ;;
    go-dyn) (cd "$o" && CGO_ENABLED=1 go build -ldflags=-linkmode=external -o "$b" "$src/hello.go") ;;
    go-small) (cd "$o" && go build -ldflags="-s -w" -o "$b" "$src/hello.go") ;;
    goose) GOOSE_CC=gcc "$GOOSE" build -O2 -o "$b" "$src/hello.goose" ;;
    goose-static) GOOSE_CC="$gccstatic" "$GOOSE" build -O2 -o "$b" "$src/hello.goose" ;;
  esac
}

now_us() { local t=$EPOCHREALTIME; echo "${t/./}"; }
med() { sort -n | sed -n "$((($1 + 1) / 2))p"; }
ms() { printf '%d.%d' $(($1 / 1000)) $(($1 % 1000 / 100)); }
kib() { printf '%d.%d' $(($1 / 1024)) $(($1 % 1024 * 10 / 1024)); }

gcc -O2 -o "$out/spawn" "$here/spawn.c" || { echo "cannot build tests/bench/spawn.c" >&2; exit 1; }

declare -A btime rtime size ssize link rss start ver
for v in $VARIANTS; do
  if ! avail "$v"; then ver[$v]="not available"; continue; fi
  echo "== $v" >&2
  ts=()
  for i in 1 2 3; do
    t0=$(now_us)
    build "$v" > "$out/build-$v.log" 2>&1 || { echo "build of $v failed; see $out/build-$v.log" >&2; failed=1; break; }
    t1=$(now_us)
    ts+=($((t1 - t0)))
  done
  [ -x "$out/$v" ] || continue
  rs=()
  for i in 1 2 3; do
    for f in "$src"/hello*.*; do echo "// edit $i" >> "$f"; done
    t0=$(now_us); build "$v" keep > "$out/rebuild-$v.log" 2>&1; t1=$(now_us); rs+=($((t1 - t0)))
  done
  rtime[$v]=$(printf '%s\n' "${rs[@]}" | med 3)
  [ "$("$out/$v" | head -n 1 | cut -c1-5)" = hello ] || { echo "$v does not print hello" >&2; failed=1; continue; }
  btime[$v]=$(printf '%s\n' "${ts[@]}" | med 3)
  size[$v]=$(stat -c %s "$out/$v")
  cp "$out/$v" "$out/$v.stripped" && strip --strip-all "$out/$v.stripped" 2> /dev/null
  ssize[$v]=$(stat -c %s "$out/$v.stripped")
  if file -L "$out/$v" | grep -q 'dynamically linked'; then link[$v]=dynamic; else link[$v]=static; fi
  rss[$v]=$(for i in 1 2 3 4 5; do /usr/bin/time -f %M "$out/$v" 2>&1 > /dev/null | tail -n 1; done | med 5)
  start[$v]=$("$out/spawn" "$N" "$out/$v") || { echo "start of $v failed" >&2; failed=1; }
done

cpu=$(grep -m1 'model name' /proc/cpuinfo 2> /dev/null | sed 's/^[^:]*: *//')
echo
echo "Machine: ${cpu:-unknown CPU}, $(nproc 2> /dev/null || echo '?') logical CPUs, $(uname -sr)"
echo
echo "Compilers: fpc $("$FPC" -iV 2> /dev/null); $(gcc --version 2> /dev/null | head -n 1);" \
  "$(rustc --version 2> /dev/null); $(go version 2> /dev/null); goose $("$GOOSE" version 2> /dev/null | head -n 1)"
echo
echo "Hello world: a clean build and a rebuild (medians of 3), the size as built and stripped, the peak RSS (median of 5), the start"
echo "(mean of $N runs)."
echo
echo "| variant | build | rebuild | size | stripped | linked | peak RSS | start |"
echo "|---|---|---|---|---|---|---|---|"
for v in $VARIANTS; do
  if [ -z "${size[$v]:-}" ]; then echo "| $v | ${ver[$v]:-failed} | | | | | | |"; continue; fi
  echo "| $v | $(ms "${btime[$v]}") ms | $(ms "${rtime[$v]}") ms | $(kib "${size[$v]}") KiB | $(kib "${ssize[$v]}") KiB | ${link[$v]} |" \
    "$(kib "${rss[$v]}") MiB | ${start[$v]:-?} us |"
done
exit $failed
