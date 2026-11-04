#!/usr/bin/env bash
# The typed mode of bpvet (tools/bpvet/bpvettyped.pas, safe/SPEC.md §20): every module of bp.pas, safe/, ext/ and
# tests/ resolves with the units it uses. The only files allowed not to resolve are the compile tests that must fail
# (*/compile/mf_*.pas): they use names the safe layer forbids. The output of the rules is checked by tests/lint.sh.
# usage: tests/typed.sh BPVET   (the binary built by tools/bpvet/build.sh; genstubs.py needs ppudump, fp-utils)
set -u
bpvet=$1
root=$(cd "$(dirname "$0")/.." && pwd)
rtl=$(mktemp -d)
trap 'rm -rf "$rtl"' EXIT
cd "$root"
python3 tools/bpvet/resolver/genstubs.py "$rtl" bp.pas safe ext tests || exit 1
dirs=(-Fu. -Fusafe -Fuext -Fisafe -Fiext -Futests/lint/units)
out=$("$bpvet" --report --typed --rtl "$rtl" "${dirs[@]}" bp.pas safe tests \
  $(find ext -maxdepth 1 -name '*.pas') 2>&1)
# ext/fpc-utf8 is built with -FaUTF8Everywhere (utf8.cfg)
out+=$'\n'$("$bpvet" --report --typed --rtl "$rtl" -FaUTF8Everywhere ext/fpc-utf8 2>&1)
printf '%s\n' "$out" | grep -E '^bpvet:'
bad=$(printf '%s\n' "$out" | grep ' Fatal: ' | grep -v '/compile/mf_')
expected=$(printf '%s\n' "$out" | grep ' Fatal: ' | grep -c '/compile/mf_')
echo "typed: $expected must-fail compile test(s) do not resolve, as expected"
if [ -n "$bad" ]; then
  printf 'FAIL typed: these files do not resolve:\n%s\n' "$bad"
  exit 1
fi
echo "typed: OK"
