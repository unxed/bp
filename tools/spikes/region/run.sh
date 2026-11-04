#!/usr/bin/env bash
# Spike 2 of unxed/bp#108 (safe/SPEC.md §20): builds regiontest.pas at -O1 and -O2 and runs it.
# FPC, FPCOPTS, RUN (e.g. qemu-aarch64) as in tests/run.sh; OUT: the build directory (default: a temporary one).
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
out=${OUT:-$(mktemp -d)}
for o in -O1 -O2; do
  mkdir -p "$out/region$o"
  # shellcheck disable=SC2086
  ${FPC:-fpc} $o ${FPCOPTS:-} -Fu"$root/ext" -Fu"$root/safe" -Fu"$root/tools/spikes/region" -FU"$out/region$o" \
    -o"$out/region$o/regiontest" "$root/tools/spikes/region/regiontest.pas" > "$out/region$o/build.log" 2>&1 \
    || { cat "$out/region$o/build.log"; exit 1; }
  echo "== region $o"
  ${RUN:-} "$out/region$o/regiontest"
done
