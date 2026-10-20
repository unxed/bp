#!/usr/bin/env bash
# Builds bpvet (safe/SPEC.md §6): tools/bpvet/build.sh OUT, where OUT is the path of the binary.
# Needs FPC with fcl-passrc (Debian, Ubuntu: fp-compiler fp-units-fcl). FPC: the compiler (default fpc).
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$(dirname "$1")"
out=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
units=$(mktemp -d)
${FPC:-fpc} -Fu"$root/safe" -Fu"$root/tools/bpvet" -FU"$units" -o"$out" "$root/tools/bpvet/bpvet.pas"
