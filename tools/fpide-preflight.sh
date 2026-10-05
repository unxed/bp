#!/bin/sh
# Fast local gate before pushing fpide changes (avoids burning GitHub runners).
# usage: tools/fpide-preflight.sh
# env:   FPIDE_PREFLIGHT_STRICT=1 — also require tools/build-fpide.sh to link fp
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
export PATH="${FPC_BIN:-$HOME/fpc-local/bin}:/usr/bin:$PATH"
command -v fpc >/dev/null || { echo "fpc not found; set FPC_BIN=" >&2; exit 1; }

out=$here/out/fpide/preflight
rm -rf "$out"
mkdir -p "$out/obj" "$out/gen"

echo "== [1/4] tv submodule"
. "$here/tools/need-tv.sh"
test -f tv/src/tvgeom.pas

echo "== [2/4] layout"
"$here/tools/check-fpide-layout.sh"

echo "== [3/4] generate shims"
python3 "$here/tools/gen-shim.py" \
  "$here/fpide/compat/shims/shims.map" "$out/gen" "$here/tv/src" | tee "$out/shims.txt"
rm -rf "$out/gen/manual"
cp -a "$here/fpide/compat/shims/manual" "$out/gen/manual"

echo "== [4/4] smoke link (shims + tv3)"
# shellcheck disable=SC2086
fpc -Mobjfpc -Sh- -Se1 \
  -Futv/src -Fu"$out/gen" -Fufpide/compat -Fi"$here/fpide/compat/shims" \
  -FU"$out/obj" -FE"$out" \
  fpide/compat/fpide_smoke.pas > "$out/smoke.log" 2>&1 || true
if [ ! -x "$out/fpide_smoke" ]; then
  echo "SMOKE FAIL — first errors:" >&2
  grep -a -E 'Error|Fatal' "$out/smoke.log" | head -40 >&2 || head -50 "$out/smoke.log" >&2
  exit 1
fi
"$out/fpide_smoke" | tee "$out/smoke.run"
grep -q 'fpide-smoke: shims+tv3 OK' "$out/smoke.run"
echo "smoke OK"

echo "== compile fp.pas (informational unless STRICT)"
export out
. "$here/tools/fpide-env.sh"
fpide_gen_shims
fpide_compile fp.pas
log=$FPIDE_OBJ/fp.log
if [ -f "$out/fp" ]; then
  echo "fp linked"
elif [ "${FPIDE_PREFLIGHT_STRICT:-0}" = 1 ]; then
  echo "STRICT: fp not linked" >&2
  grep -a -E 'Error|Fatal' "$log" | head -40 >&2 || true
  exit 1
else
  echo "fp not linked yet (expected until object→class). Top errors:"
  grep -a -E 'Error|Fatal' "$log" | head -20 || echo "(see $log)"
fi

echo "PREFLIGHT OK"
