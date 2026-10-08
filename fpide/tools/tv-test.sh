#!/bin/sh
# tv3 unit tests: tools/test.sh of tv/ (the tests side by side). usage: tools/tv-test.sh [t_name ...]
# needs: fpc (TV_FPC picks another one)
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
FPC=${TV_FPC:-${FPC:-fpc}} TV_TEST_WORK=${TV_TEST_WORK:-$here/build/tv-tests} exec "$here/tv/tools/test.sh" "$@"
