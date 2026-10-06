#!/bin/sh
# Build the Text Mode IDE (fp) with the Free Pascal compiler found on the PATH (or $FPC).
# usage: tools/build-fpide.sh [TARGET] [OUTDIR]     TARGET defaults to the one of this system (linux64)
# FPIDE_EMBED=1 links the compiler of FPC into the IDE as the original does (fetches ~400 MB of FPC sources);
# by default the IDE runs the external fpc and gdb and nothing but fpide/, tv/ and fpc is needed.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
target=${1:-auto}
fpc_bin=${FPC:-fpc}
command -v "$fpc_bin" >/dev/null 2>&1 || { echo "no Free Pascal compiler ($fpc_bin) on the PATH: sudo apt-get install fp-compiler fp-units-rtl fp-units-fcl fp-units-base fp-units-misc fp-units-gfx" >&2; exit 1; }
if [ "$target" = auto ]; then
    case "$("$fpc_bin" -iSO)-$("$fpc_bin" -iSP)" in
        linux-x86_64) target=linux64 ;;
        *) echo "no default target for $("$fpc_bin" -iSO)-$("$fpc_bin" -iSP): only linux64 is supported yet" >&2; exit 1 ;;
    esac
    echo "== target: $target (this system)"
fi
suffix=""
[ "${FPIDE_EMBED:-0}" = 0 ] || suffix="-embed"
out=${2:-$here/out/fpide/$target$suffix}
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
rm -f "$out/fp"   # a failed compile must not leave (and report) the previous binary
fpide_compile fp.pas
log="$FPIDE_OBJ/fp.log"
grep -a -E 'Error|Fatal|Warning:' "$log" | head -40 || true
if [ -f "$out/fp" ]; then
    echo "built: $out/fp"
    exit 0
fi
echo "fp was not linked (log: $log)" >&2
exit 1
