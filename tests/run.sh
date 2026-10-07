#!/usr/bin/env bash
# Тесты Better Pascal. Всё собирается БЕЗ опций компилятора (кроме путей к слоям): репозиторий
# копируется в рабочую папку, как у пользователя (safe/SPEC.md §2).
#   tests/safe/test_*.pas   слой safe: гоняется дважды — с unit Safe и с unit BP (имя Safe заменяется на BP)
#   tests/ext/test_*.pas    слой ext (UTF-8, горутины, потоки): только с unit BP
#   compile/mf_*.pas        первая строка "// EXPECT: fail|warn SAFE-Sx", "clean", "run" (clean + код 0)
#                           или "exit N" (собирается, завершается с кодом N)
# usage: tests/run.sh [safe|ext|all]      (по умолчанию all)
# Переменные окружения (для CI; по умолчанию — голый fpc на хосте):
#   FPC          компилятор (кросс: ppcrossa64 ...)        FPCOPTS  его опции (-dSAFE_LIBC, -Tlinux -XP...)
#   RUN          префикс запуска (qemu-aarch64)            OUT      куда положить бинарники (иначе mktemp)
#   SKIP         тесты, которые пропустить ("test_ffi")    NO_COMPILE_CHECKS=1 — без compile/*.pas
set -u
FPC=${FPC:-fpc}
FPCOPTS=${FPCOPTS:-}
RUN=${RUN:-}
SKIP=${SKIP:-}
layers=${1:-all}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
work=${OUT:-$(mktemp -d)}
mkdir -p "$work"
# the library keeps its layout (bp.pas, safe/, ext/): the include files are found next to the units
mkdir -p "$work/lib"
cp "$root/bp.pas" "$work/lib/"
cp -r "$root/safe" "$root/ext" "$work/lib/"
LIBOPTS="-Fu$work/lib -Fu$work/lib/safe -Fu$work/lib/ext"
fail=0

# $1 = directory with the test sources, $2 = suffix for the build dir, $3 = "bp": replace unit Safe with BP, "raw": as is
run_layer() {
  local src=$1 name=$2 mode=$3 dir="$work/$2"
  mkdir -p "$dir/compile"
  cp "$src"/*.pas "$dir/" 2>/dev/null
  cp "$src"/compile/*.pas "$dir/compile/" 2>/dev/null
  if [ "$mode" = bp ]; then
    sed -i -E 's/\bSafe\b/BP/g' "$dir"/*.pas "$dir"/compile/*.pas 2>/dev/null
    # BP must be FIRST in the uses of a program (the thread manager, see bp.pas); the compile checks keep it last
    local f
    for f in "$dir"/test_*.pas; do
      [ -e "$f" ] || continue
      perl -0pi -e 's/,\s*BP\s*;/;/; s/\buses\b(\s*)/uses BP,$1/' "$f"
    done
  fi
  cd "$dir" || return 1
  local t
  for t in test_*.pas; do
    [ -e "$t" ] || continue
    t=${t%.pas}
    case " $SKIP " in *" $t "*) echo "== skip $t ($name)"; continue ;; esac
    echo "== build $t ($name)"
    if $FPC $FPCOPTS $LIBOPTS -FU"$dir" "$t.pas" > build.log 2>&1; then
      grep -E 'Warning|Note|Hint' build.log | grep -v "$t.pas" || true
      echo "== run $t ($name)"
      timeout 300 $RUN "./$t" || fail=1
    else
      cat build.log; fail=1
    fi
  done
  [ "${NO_COMPILE_CHECKS:-}" = 1 ] && return 0
  echo "== compile checks ($name)"
  cd "$dir/compile" 2>/dev/null || return 0
  cp "$dir"/*.pas . 2>/dev/null   # test units (ffi_libc) next to the checks
  local f read_kind
  for f in mf_*.pas; do
    [ -e "$f" ] || continue
    read -r _ _ kind rule < "$f"
    if $FPC $FPCOPTS $LIBOPTS -FU"$dir/compile" "$f" > log 2>&1; then built=yes; else built=no; fi
    case "$kind" in
      fail)  ok=$([ $built = no ] && grep -q "$rule" log && echo 1) ;;
      warn)  ok=$([ $built = yes ] && grep -q "$rule" log && echo 1) ;;
      clean) ok=$([ $built = yes ] && ! grep -q 'SAFE-' log && echo 1) ;;
      run)   ok=$([ $built = yes ] && ! grep -q 'SAFE-' log && timeout 60 "./${f%.pas}" && echo 1) ;;
      exit)  ok=$([ $built = yes ] && { timeout 60 "./${f%.pas}" > out 2>&1; [ $? = "$rule" ]; } && echo 1) ;;
    esac
    if [ "${ok:-}" = 1 ]; then echo "ok   $f ($kind $rule)"
    else echo "FAIL $f (expected $kind $rule, built=$built):"; grep -E 'Error|Warning|Fatal' log | head -5; fail=1; fi
    ok=
  done
}

$FPC -iV
case "$layers" in safe|all)
  run_layer "$here/safe" safe-Safe safe
  run_layer "$here/safe" safe-BP bp ;;
esac
case "$layers" in ext|all)
  run_layer "$here/ext" ext-BP raw ;;
esac
exit $fail
