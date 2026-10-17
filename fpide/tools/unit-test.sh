#!/bin/sh
# fpide unit tests (fpide/tests/unit/t_*.pas): each one is built with the options of fpide-env.sh and run.
# usage: fpide/tools/unit-test.sh [t_name ...]     (no arguments: every t_*.pas)
# needs: fpc with the rtl and fcl units, the tv/ and tve/ submodules
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
. "$here/tools/need-tv.sh"
out=${FPIDE_UNIT_OUT:-$here/out/unit}
mkdir -p "$out"
. "$here/tools/fpide-env.sh"
fpide_gen_shims

if [ $# -gt 0 ]; then
    tests=$*
else
    tests=$(cd "$here/tests/unit" && ls t_*.pas | sed 's/\.pas$//')
fi

fail=0
for t in $tests; do
    rm -f "$out/$t"
    log=$FPIDE_OBJ/$t.log
    # shellcheck disable=SC2086
    ${FPC:-fpc} $FPIDE_OPTS "$here/tests/unit/$t.pas" > "$log" 2>&1 || true
    if [ ! -x "$out/$t" ]; then
        echo "== $t: BUILD FAILED" >&2
        grep -a -E 'Error|Fatal' "$log" | head -40 >&2 || tail -40 "$log" >&2
        fail=1
        continue
    fi
    echo "== $t"
    if ! "$out/$t"; then
        echo "== $t: FAILED" >&2
        fail=1
    fi
done
exit $fail
