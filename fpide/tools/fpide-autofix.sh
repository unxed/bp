#!/bin/sh
# Build fp.pas and apply the mechanical class-port fixers until they stop changing anything.
# usage: fpide/tools/fpide-autofix.sh [max-errors-shown]        env: CC_ITER (default 8), CC_EXTRA (fpc flags)
# Fixers (each patches only the lines FPC names): fpide-nested-cast.py, fpide-ptrcast.py,
# fpide-derefcast.py. Objects go to out/preflight/obj2 (no -Ur: units are rebuilt on change).
here=$(cd "$(dirname "$0")/.." && pwd); out=$here/out/preflight
cd "$here"; export PATH=/usr/bin:$PATH; export FPIDE_OBJ=$out/obj2; mkdir -p "$FPIDE_OBJ"
export FPIDE_EXTRA="-Se500 -vewn ${CC_EXTRA:-}"; . "$here/tools/fpide-env.sh"
fpide_gen_shims
i=0
while [ $i -lt "${CC_ITER:-8}" ]; do
  i=$((i+1))
  fpide_compile fp.pas
  a=$(python3 "$here/tools/fpide-nested-cast.py" "$FPIDE_OBJ/fp.log" "$here/src")
  b=$(python3 "$here/tools/fpide-ptrcast.py" "$FPIDE_OBJ/fp.log" "$here/src")
  c=$(python3 "$here/tools/fpide-derefcast.py" "$FPIDE_OBJ/fp.log" "$here/src")
  echo "iter $i: $a; $b; $c"
  case "$a;$b;$c" in *"patched 0 "*" 0 casts"*"removed 0 "*) break;; esac
done
grep -a -E 'Error|Fatal' "$FPIDE_OBJ/fp.log" | grep -v "Found declaration" | head -"${1:-15}"
ls -la "$out/fp" 2>/dev/null
