#!/bin/sh
# Materialize fpide/src and fpide/fpc-compiler from a bootstrap run (or run fetch first).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-$root/build/bootstrap-fpide}
"$here/run.sh" "$out"
rm -rf "$root/fpide/src" "$root/fpide/fpc-compiler"
cp -a "$out/staging-ide" "$root/fpide/src"
cp -a "$out/staging-compiler" "$root/fpide/fpc-compiler"
echo "materialized fpide/src and fpide/fpc-compiler"
