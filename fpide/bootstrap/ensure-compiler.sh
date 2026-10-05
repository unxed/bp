#!/bin/sh
# Ensure FPC compiler/ is staged for builds (not in git). Idempotent if pin matches.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
. "$here/upstream.env"
out=${FPIDE_BOOTSTRAP:-$root/build/bootstrap-fpide}
marker=$out/staging-compiler/.fpide-fpc-commit
if [ -f "$marker" ] && [ "$(cat "$marker")" = "$FPC_COMMIT" ] && [ -f "$out/staging-compiler/finput.pas" ]; then
    echo "compiler ready: $out/staging-compiler (@ $FPC_COMMIT)"
    exit 0
fi
"$here/run.sh" "$out"
echo "$FPC_COMMIT" > "$out/staging-compiler/.fpide-fpc-commit"
echo "compiler ready: $out/staging-compiler"
