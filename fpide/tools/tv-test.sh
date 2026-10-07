#!/bin/sh
# tv3 unit tests (from unxed/dn tools/tv-test.sh).
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
if [ -f "$here/tv/tools/class-gate.sh" ]; then "$here/tv/tools/class-gate.sh"; fi
w=${TV_TEST_WORK:-$here/build/tv-tests}; mkdir -p "$w"
cd "$here/tv/tests"
if [ $# -gt 0 ]; then tests=$(for n in "$@"; do echo "${n%.pas}.pas"; done); else tests=$(ls t_*.pas); fi
fail=0
for t in $tests; do
    n=${t%.pas}
    out=$(${TV_FPC:-fpc} -Fu../src -Fu. -FU"$w" -FE"$w" "$t" 2>&1) || true
    if echo "$out" | grep -qE "Error|Fatal"; then echo "BUILD FAIL $n"; echo "$out" | grep -E "Error|Fatal" | head -3; fail=1; continue; fi
    ${TV_RUN:-} "$w/$n" > "$w/$n.txt" 2>&1 || true
    r=$(tail -1 "$w/$n.txt"); echo "$n: $r"
    case "$r" in "ALL OK"*) ;; *) fail=1; grep -E '^FAIL' "$w/$n.txt" | head -10;; esac
done
exit $fail
