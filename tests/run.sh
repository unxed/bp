#!/usr/bin/env bash
# Better Pascal tests. Everything is built WITHOUT compiler options (except the layer paths): the repository
# is copied to a working folder, as for a user (safe/SPEC.md §2).
#   tests/safe/test_*.pas   the safe layer: run twice — with unit Safe and with unit BP (the name Safe is replaced with BP)
#   tests/ext/test_*.pas    the ext layer (UTF-8, goroutines, threads): with unit BP only
#   compile/mf_*.pas        first line "// EXPECT: fail|warn SAFE-Sx", "clean", "run" (clean + exit code 0)
#                           or "exit N" (builds, terminates with exit code N)
# usage: tests/run.sh [safe|ext|all]      (default: all)
# Environment variables (for CI; by default — bare fpc on the host):
#   FPC          compiler (cross: ppcrossa64 ...)          FPCOPTS  its options (-dSAFE_LIBC, -Tlinux -XP...)
#   RUN          run prefix (qemu-aarch64)                 OUT      where to put binaries (otherwise mktemp)
#   SKIP         tests to skip ("test_ffi")                NO_COMPILE_CHECKS=1 — without compile/*.pas
set -u
FPC=${FPC:-fpc}
FPCOPTS=${FPCOPTS:-}
RUN=${RUN:-}
SKIP=${SKIP:-}
layers=${1:-all}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
work=${OUT:-$(mktemp -d)}
mkdir -p "$work"
# the library keeps its layout (bp.pas, safe/, ext/): the include files are found next to the units
mkdir -p "$work/lib"
cp "$root/bp.pas" "$work/lib/"
cp -r "$root/safe" "$root/ext" "$work/lib/"
LIBOPTS="-Fu$work/lib -Fu$work/lib/safe -Fu$work/lib/ext"
fail=0

# $1 = directory with the test sources, $2 = suffix for the build dir, $3 = "bp": replace unit Safe with BP, "raw": as is
run_layer() {
  local src=$1 name=$2 mode=$3 dir="$work/$2"
  mkdir -p "$dir/compile"
  cp "$src"/*.pas "$dir/" 2>/dev/null
  cp "$src"/compile/*.pas "$dir/compile/" 2>/dev/null
  if [ "$mode" = bp ]; then
    sed -i -E 's/\bSafe\b/BP/g' "$dir"/*.pas "$dir"/compile/*.pas 2>/dev/null
    # BP must be FIRST in the uses of a program (the thread manager, see bp.pas); the compile checks keep it last
    local f
    for f in "$dir"/test_*.pas; do
      [ -e "$f" ] || continue
      perl -0pi -e 's/,\s*BP\s*;/;/; s/\buses\b(\s*)/uses BP,$1/' "$f"
    done
  fi
  cd "$dir" || return 1
  local t
  for t in test_*.pas; do
    [ -e "$t" ] || continue
    t=${t%.pas}
    case " $SKIP " in *" $t "*) echo "== skip $t ($name)"; continue ;; esac
    echo "== build $t ($name)"
    if $FPC $FPCOPTS $LIBOPTS -FU"$dir" "$t.pas" > build.log 2>&1; then
      grep -E 'Warning|Note|Hint' build.log | grep -v "$t.pas" || true
      echo "== run $t ($name)"
      timeout 300 $RUN "./$t" || fail=1
    else
      cat build.log; fail=1
    fi
  done
  [ "${NO_COMPILE_CHECKS:-}" = 1 ] && return 0
  echo "== compile checks ($name)"
  cd "$dir/compile" 2>/dev/null || return 0
  cp "$dir"/*.pas . 2>/dev/null   # test units (ffi_libc) next to the checks
  local f read_kind
  for f in mf_*.pas; do
    [ -e "$f" ] || continue
    read -r _ _ kind rule < "$f"
    if $FPC $FPCOPTS $LIBOPTS -FU"$dir/compile" "$f" > log 2>&1; then built=yes; else built=no; fi
    case "$kind" in
      fail)  ok=$([ $built = no ] && grep -q "$rule" log && echo 1) ;;
      warn)  ok=$([ $built = yes ] && grep -q "$rule" log && echo 1) ;;
      clean) ok=$([ $built = yes ] && ! grep -q 'SAFE-' log && echo 1) ;;
      run)   ok=$([ $built = yes ] && ! grep -q 'SAFE-' log && timeout 60 "./${f%.pas}" && echo 1) ;;
      exit)  ok=$([ $built = yes ] && { timeout 60 "./${f%.pas}" > out 2>&1; [ $? = "$rule" ]; } && echo 1) ;;
    esac
    if [ "${ok:-}" = 1 ]; then echo "ok   $f ($kind $rule)"
    else echo "FAIL $f (expected $kind $rule, built=$built):"; grep -E 'Error|Warning|Fatal' log | head -5; fail=1; fi
    ok=
  done
}

$FPC -iV
case "$layers" in safe|all)
  run_layer "$here/safe" safe-Safe safe
  run_layer "$here/safe" safe-BP bp ;;
esac
case "$layers" in ext|all)
  run_layer "$here/ext" ext-BP raw ;;
esac
exit $fail
