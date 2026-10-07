#!/bin/sh
# One command: everything needed to build fp (the IDE on tv3) and, if asked, to run its tests.
#   fpide/tools/fpide-setup-build.sh          install missing packages (Debian/Ubuntu), fetch tv/, build with the fpc of the system
#   fpide/tools/fpide-setup-build.sh test     ... and then run the tmux acceptance tests (fpide/tools/fpide-accept.sh)
# Result: out/linux64/fp.  Run it with TV_FAR2L=0 in terminals that do not answer far2l queries.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
pkgs="fp-compiler fp-units-rtl fp-units-fcl fp-units-base fp-units-misc fp-units-gfx gdb tmux python3 git"

if ! command -v fpc >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        sudo=""
        [ "$(id -u)" = 0 ] || sudo=sudo
        $sudo apt-get update
        # shellcheck disable=SC2086
        $sudo apt-get install -y --no-install-recommends $pkgs
    else
        echo "fpc/tmux not found and no apt-get: install Free Pascal 3.2.x (rtl, fcl, base, misc units), tmux, python3" >&2
        exit 1
    fi
fi

git -C "$here" submodule update --init --depth 1 tv
"$here/tools/build-fpide.sh"
fp=$here/out/linux64/fp
[ -x "$fp" ] || { echo "build failed: see $here/out/linux64/obj/fp.log" >&2; exit 1; }
# build-fpide.sh keeps an old fp if a rebuild fails: refuse a binary older than the sources
if [ -n "$(find "$here/src" "$here/tv/src" -newer "$fp" \( -name '*.pas' -o -name '*.inc' \) 2>/dev/null | head -1)" ]; then
    echo "build failed: fp is older than the sources, see $here/out/linux64/obj/fp.log" >&2
    exit 1
fi
echo "built: $fp"
[ "${1:-}" = test ] && exec "$here/tools/fpide-accept.sh" "$fp"
exit 0
