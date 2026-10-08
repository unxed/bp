#!/bin/sh
# tv3 tests through a pty (the demo, the terminal view, the clipboard, the far2l extensions): tools/pty-test.sh of tv/ (the tests
# side by side, each with a HOME of its own).
# needs: fpc (TV_FPC picks another one), python3
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
FPC=${TV_FPC:-${FPC:-fpc}} TV_PTY_WORK=${TV_TEST_WORK:-$here/build/tv-pty-tests} exec "$here/tv/tools/pty-test.sh" "$@"
