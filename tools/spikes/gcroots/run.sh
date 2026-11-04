#!/usr/bin/env bash
# Spike 3 of unxed/bp#108 (safe/SPEC.md §20): builds gcroots.pas at -O1 and -O2 and runs it.
# FPC, FPCOPTS, RUN (e.g. qemu-aarch64) as in tests/run.sh; OUT: the build directory (default: a temporary one).
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
out=${OUT:-$(mktemp -d)}
for o in -O1 -O2; do
  mkdir -p "$out/gcroots$o"
  # shellcheck disable=SC2086
  ${FPC:-fpc} $o ${FPCOPTS:-} -Fu"$root/ext" -Fu"$root/safe" -FU"$out/gcroots$o" -o"$out/gcroots$o/gcroots" \
    "$root/tools/spikes/gcroots/gcroots.pas" > "$out/gcroots$o/build.log" 2>&1 || { cat "$out/gcroots$o/build.log"; exit 1; }
  echo "== gcroots $o"
  ${RUN:-} "$out/gcroots$o/gcroots"
done
