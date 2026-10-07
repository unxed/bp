#!/bin/sh
# Fast local gate before pushing fpide changes (avoids burning GitHub runners).
# usage: fpide/tools/fpide-preflight.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
export PATH="${FPC_BIN:-$HOME/fpc-local/bin}:/usr/bin:$PATH"
command -v fpc >/dev/null || { echo "fpc not found; set FPC_BIN=" >&2; exit 1; }

out=$here/out/preflight
rm -rf "$out"
mkdir -p "$out/obj" "$out/gen"

echo "== [1/4] tv submodule"
. "$here/tools/need-tv.sh"
test -f tv/src/tvgeom.pas

echo "== [2/4] layout"
"$here/tools/check-fpide-layout.sh"

echo "== [3/4] generate shims"
python3 "$here/tools/gen-shim.py" \
  "$here/compat/shims/shims.map" "$out/gen" "$here/tv/src" | tee "$out/shims.txt"
rm -rf "$out/gen/manual"
cp -a "$here/compat/shims/manual" "$out/gen/manual"

echo "== [4/4] smoke link (shims + tv3)"
# shellcheck disable=SC2086
fpc -Mobjfpc -Sh- -Se1 \
  -Futv/src -Fu"$out/gen" -Fucompat -Fi"$here/compat/shims" \
  -FU"$out/obj" -FE"$out" \
  compat/fpide_smoke.pas > "$out/smoke.log" 2>&1 || true
if [ ! -x "$out/fpide_smoke" ]; then
  echo "SMOKE FAIL — first errors:" >&2
  grep -a -E 'Error|Fatal' "$out/smoke.log" | head -40 >&2 || head -50 "$out/smoke.log" >&2
  exit 1
fi
"$out/fpide_smoke" | tee "$out/smoke.run"
grep -q 'fpide-smoke: shims+tv3 OK' "$out/smoke.run"
echo "smoke OK"

echo "== compile fp.pas (system fpc; no compiler sources needed)"
export out
. "$here/tools/fpide-env.sh"
fpide_gen_shims
fpide_compile fp.pas
log=$FPIDE_OBJ/fp.log
if [ ! -f "$out/fp" ]; then
  echo "fp was not linked" >&2
  grep -a -E 'Error|Fatal' "$log" | head -40 >&2 || true
  exit 1
fi
echo "fp linked"
if grep -a -q 'inherited method is hidden' "$log" 2>/dev/null; then
  grep -a 'inherited method is hidden' "$log" | grep -v 'Update(LongInt)' | sort -u > "$FPIDE_OBJ/hidden.txt" || true
  if [ -s "$FPIDE_OBJ/hidden.txt" ]; then
    echo "a method lost its override:" >&2
    cat "$FPIDE_OBJ/hidden.txt" >&2
    exit 1
  fi
fi

echo "PREFLIGHT OK"
