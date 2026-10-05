#!/bin/sh
# Build Text Mode IDE (fp) for one target. Heavy work — prefer CI.
# usage: tools/build-fpide.sh linux64 [OUTDIR]
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
target=${1:?usage: tools/build-fpide.sh linux64 [OUTDIR]}
out=${2:-$here/out/fpide/$target}
mkdir -p "$out"
case "$target" in
    linux64) FPIDE_OPTS_EXTRA="-Tlinux -Px86_64" ;;
    *) echo "unsupported target: $target" >&2; exit 1 ;;
esac
export FPIDE_EXTRA="${FPIDE_OPTS_EXTRA} ${FPIDE_EXTRA:-}"
. "$here/tools/fpide-env.sh"
echo "== shims (FV names → tv3)"
fpide_gen_shims
echo "== compile fp.pas ($target)"
fpide_compile fp.pas
log="$FPIDE_OBJ/fp.log"
grep -a -E 'Error|Fatal|Warning:' "$log" | head -40 || true
if [ -f "$out/fp" ]; then
    echo "built: $out/fp"
    exit 0
fi
echo "fp was not linked (log: $log)" >&2
exit 1
