#!/usr/bin/env bash
# Runs the spike over every module of safe/, ext/ and tests/ (tests/lint excluded): tools/bpvet/spike/run.sh RSPIKE
# RSPIKE is the binary built from rspike.pas against a pasresolver.pp with the fix of safe/SPEC.md §20 "Spike 1 result".
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
stub=$(cd "$(dirname "$0")/stub" && pwd)
cd "$root"
for f in $(git ls-files 'safe/*.pas' 'ext/*.pas' 'tests/*.pas' 'bp.pas' | grep -v '^tests/lint/'); do
  timeout 20 "$1" "$root/$f" "$stub" "$root/$(dirname "$f")" "$root/safe" "$root/ext" "$root" "$root/tests/safe" "$root/tests/ext" | head -1
done
