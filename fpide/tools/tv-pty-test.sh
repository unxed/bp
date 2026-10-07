#!/bin/sh
# tv3 tests through a pty that need no screen emulator: the far2l terminal extensions, the client (TvUnix against a fake terminal in Python) and the server (TvVt).
# needs: fpc, python3
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
w=${TV_TEST_WORK:-$here/build/tv-pty-tests}; mkdir -p "$w"
cd "$here/tv/tests/pty"
for p in f2l_clip f2l_ext rundemo2; do
    out=$(${TV_FPC:-fpc} -Fu../../src -Fu.. -FU"$w" -FE"$w" "$p.pas" 2>&1) || true
    if echo "$out" | grep -qE "Error|Fatal"; then echo "BUILD FAIL $p"; echo "$out" | grep -E "Error|Fatal" | head -3; exit 1; fi
done
status=0
python3 test_far2l.py "$w/f2l_clip" || status=1
python3 test_far2l_ext.py "$w/f2l_ext" || status=1
python3 test_far2l_vt.py "$w/rundemo2" "$w/f2l_ext" || status=1
exit $status
