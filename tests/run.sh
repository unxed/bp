#!/usr/bin/env bash
# Тесты Safe Pascal. Всё собирается БЕЗ опций компилятора: файлы копируются
# в одну папку с safe.pas, как у пользователя (SPEC §2).
#   test_*.pas         — рантайм; код возврата = число провалов
#   compile/*.pas      — первая строка "// EXPECT: fail|warn SAFE-Sx", "clean", "run" (clean + код 0)
#                        или "exit N" (собирается, завершается с кодом N)
# Переменные окружения (для CI; по умолчанию — голый fpc на хосте):
#   FPC          компилятор (кросс: ppcrossa64 ...)        FPCOPTS  его опции (-dSAFE_LIBC, -Tlinux -XP...)
#   RUN          префикс запуска (qemu-aarch64)            OUT      куда положить бинарники (иначе mktemp)
#   SKIP         тесты, которые пропустить ("test_ffi")    NO_COMPILE_CHECKS=1 — без compile/*.pas
set -u
FPC=${FPC:-fpc}
FPCOPTS=${FPCOPTS:-}
RUN=${RUN:-}
SKIP=${SKIP:-}
here=$(cd "$(dirname "$0")" && pwd)
work=${OUT:-$(mktemp -d)}
mkdir -p "$work"
cp "$here"/../*.pas "$here"/*.pas "$here"/compile/*.pas "$work/"
cd "$work"
$FPC -iV
fail=0

for t in test_*.pas; do
  t=${t%.pas}
  case " $SKIP " in *" $t "*) echo "== skip $t"; continue ;; esac
  echo "== build $t"
  if $FPC $FPCOPTS "$t.pas" > build.log 2>&1; then
    grep -E 'Warning|Note|Hint' build.log | grep -v "$t.pas" || true
    echo "== run $t"
    timeout 300 $RUN "./$t" || fail=1
  else
    cat build.log; fail=1
  fi
done

[ "${NO_COMPILE_CHECKS:-}" = 1 ] && exit $fail
echo "== compile checks"
for f in mf_*.pas; do
  read -r _ _ kind rule < "$f"
  if $FPC $FPCOPTS "$f" > log 2>&1; then built=yes; else built=no; fi
  case "$kind" in
    fail)  ok=$([ $built = no ] && grep -q "$rule" log && echo 1) ;;
    warn)  ok=$([ $built = yes ] && grep -q "$rule" log && echo 1) ;;
    clean) ok=$([ $built = yes ] && ! grep -q 'SAFE-' log && echo 1) ;;
    run)   ok=$([ $built = yes ] && ! grep -q 'SAFE-' log && timeout 60 "./${f%.pas}" && echo 1) ;;
    exit)  ok=$([ $built = yes ] && { timeout 60 "./${f%.pas}" > out 2>&1; [ $? = "$rule" ]; } && echo 1) ;;
  esac
  if [ "${ok:-}" = 1 ]; then echo "ok   $f ($kind $rule)"
  else echo "FAIL $f (expected $kind $rule, built=$built):"; grep -E 'Error|Warning|Fatal' log | head -5; fail=1; fi
done
exit $fail
