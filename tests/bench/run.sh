#!/usr/bin/env bash
# Benchmarks of Better Pascal (report only, no thresholds; safe/SPEC.md, register H3).
# usage: tests/bench/run.sh [out-dir]       FPC — the compiler (default fpc)
set -eu
FPC=${FPC:-fpc}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-$(mktemp -d)}
mkdir -p "$out"
for src in "$here"/bench_*.pas; do
  name=$(basename "$src" .pas)
  "$FPC" -O2 -Fu"$root/safe" -FU"$out" -FE"$out" "$src"
  "$out/$name"
done
