#!/bin/sh
# Acceptance tests of fpide on tv3 (fpide/tests/accept): build fp, then drive it in tmux. The tests wait for the program, not for
# the CPU, so they all run side by side: test_accept.py, test_config.py, every section of test_functions.py and the menu sweep
# (with -j $FPIDE_SWEEP_J copies of the IDE, default 8), each with a HOME and XDG directories of its own.
# usage: fpide/tools/fpide-accept.sh [PATH/TO/fp]     (default: build with tools/build-fpide.sh linux64)
# The logs go to $FPIDE_ACCEPT_LOGS (default: a new temp dir); the summary lists each test, its time and its last line.
# needs: fpc (fp-compiler, fp-units-*), tmux, python3
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
fp=${1:-}
if [ -z "$fp" ]; then
  "$here/tools/build-fpide.sh"
  fp=$here/out/linux64/fp
fi
fp=$(cd "$(dirname "$fp")" && pwd)/$(basename "$fp")
acc=$here/tests/accept
logs=${FPIDE_ACCEPT_LOGS:-$(mktemp -d "${TMPDIR:-/tmp}/fpide-accept.XXXXXX")}
mkdir -p "$logs"
# Delve installed by go install is in ~/go/bin; the tests get other HOMEs
[ -d "$HOME/go/bin" ] && PATH="$HOME/go/bin:$PATH" && export PATH

sections=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import test_functions as t; print(' '.join(n for n, _ in t.SECTIONS))" "$acc")
jobs="accept:test_accept.py config:test_config.py sweep:test_menu_sweep.py"
for s in $sections exit; do jobs="$jobs functions-$s:test_functions.py"; done

start=$(date +%s)
for j in $jobs; do
  name=${j%%:*}; script=${j#*:}
  args=
  case $name in
    functions-*) args=${name#functions-} ;;
    sweep) args="-j ${FPIDE_SWEEP_J:-8}" ;;
  esac
  (
    HOME=$logs/home-$name
    XDG_CONFIG_HOME=$HOME/.config XDG_STATE_HOME=$HOME/.local/state XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
    export HOME XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME
    mkdir -p "$HOME"
    t0=$(date +%s)
    # shellcheck disable=SC2086
    if python3 "$acc/$script" "$fp" $args > "$logs/$name.log" 2>&1; then echo 0 > "$logs/$name.rc"; else echo 1 > "$logs/$name.rc"; fi
    echo $(( $(date +%s) - t0 )) > "$logs/$name.time"
  ) &
done
wait

status=0
for j in $jobs; do
  name=${j%%:*}
  rc=$(cat "$logs/$name.rc" 2>/dev/null || echo 1)
  if [ "$rc" = 0 ]; then r=ok; else r=FAILED; status=1; fi
  printf '%-22s %-6s %4ss  %s\n' "$name" "$r" "$(cat "$logs/$name.time" 2>/dev/null)" "$(tail -1 "$logs/$name.log")"
  [ "$rc" = 0 ] || grep -E '^FAIL' "$logs/$name.log" | head -10 | sed 's/^/    /'
done
echo "wall time $(( $(date +%s) - start ))s; logs: $logs"
exit $status
