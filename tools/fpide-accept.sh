#!/bin/sh
# Acceptance tests of fpide on tv3 (fpide/tests/accept): build fp, then drive it in tmux.
# usage: tools/fpide-accept.sh [PATH/TO/fp]     (default: build with tools/build-fpide.sh linux64)
# needs: fpc (fp-compiler, fp-units-*), tmux, python3
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
fp=${1:-}
if [ -z "$fp" ]; then
  "$here/tools/build-fpide.sh"
  fp=$here/out/fpide/linux64/fp
fi
status=0
python3 "$here/fpide/tests/accept/test_accept.py" "$fp" || status=1
python3 "$here/fpide/tests/accept/test_menu_sweep.py" "$fp" || status=1
exit $status
