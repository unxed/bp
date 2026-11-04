#!/usr/bin/env bash
# Spike 4 of unxed/bp#108 (safe/SPEC.md §21.3): builds mntest.pas at -O1 and -O2 (guard areas) and at -O2 -Ct (no guard,
# the stack check of the compiler) and runs it; with a guard, an endless recursion in a goroutine must stop the process.
# FPC, FPCOPTS, RUN (e.g. qemu-aarch64) as in tests/run.sh; OUT: the build directory (default: a temporary one).
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
out=${OUT:-$(mktemp -d)}
for o in -O1 -O2 "-O2 -Ct"; do
  d="$out/mn${o// /}"
  mkdir -p "$d"
  # shellcheck disable=SC2086
  ${FPC:-fpc} $o ${FPCOPTS:-} -Fu"$root" -Fu"$root/ext" -Fu"$root/safe" -Fu"$root/tools/spikes/mn" -FU"$d" \
    -o"$d/mntest" "$root/tools/spikes/mn/mntest.pas" > "$d/build.log" 2>&1 || { cat "$d/build.log"; exit 1; }
  echo "== mn $o"
  ${RUN:-} "$d/mntest"
  if [ "$o" != "-O2 -Ct" ]; then
    rc=0
    (ulimit -c 0; exec ${RUN:-} "$d/mntest" overflow) > "$d/overflow.log" 2>&1 || rc=$?
    if [ "$rc" = 0 ] || grep -q FAIL "$d/overflow.log"; then
      echo "FAIL an overflow into the guard area did not stop the process"
      cat "$d/overflow.log"
      exit 1
    fi
    echo "ok   an endless recursion in a goroutine hits the guard area and stops the process (exit $rc)"
  fi
done
