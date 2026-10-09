# Sourced by fpide build scripts: tv/ is submodule https://github.com/unxed/tv3, tve/ is https://github.com/unxed/tve
here=${here:-$(cd "$(dirname "$0")/.." && pwd)}
if [ -n "${FPIDE_TV:-}" ] && [ ! -e "$here/tv/src" ]; then
    rmdir "$here/tv" 2>/dev/null || true
    ln -s "$FPIDE_TV" "$here/tv"
fi
if [ ! -f "$here/tv/src/tvgeom.pas" ]; then
    echo "tv/ is empty: git submodule update --init fpide/tv" >&2
    git -C "$here" submodule update --init --depth 1 tv >&2 ||
        { echo "ERROR: no tv/. Run: git submodule update --init tv  (in fpide/)" >&2; exit 1; }
fi
if [ -z "${FPIDE_TV:-}" ] && git -C "$here" submodule status tv 2>/dev/null | grep -q '^[+-]'; then
    echo "NOTE: tv/ is not at the commit recorded in sp; git submodule update --init fpide/tv" >&2
fi
if [ -n "${FPIDE_TVE:-}" ] && [ ! -e "$here/tve/src" ]; then
    rmdir "$here/tve" 2>/dev/null || true
    ln -s "$FPIDE_TVE" "$here/tve"
fi
if [ ! -f "$here/tve/src/tvebuf.pas" ]; then
    echo "tve/ is empty: git submodule update --init fpide/tve" >&2
    git -C "$here" submodule update --init --depth 1 tve >&2 ||
        { echo "ERROR: no tve/. Run: git submodule update --init tve  (in fpide/)" >&2; exit 1; }
fi
