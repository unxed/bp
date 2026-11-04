#!/usr/bin/env bash
# tools/bp build (safe/SPEC.md §16): a program in the region style is checked, built and runs; a program with a use
# after Release is not built. Needs ppudump (fp-utils) for the stubs.
# usage: tests/bp.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BP_CACHE=$tmp/cache
mkdir -p "$tmp/ok" "$tmp/bad"
sed '1,2d' "$root/tests/lint/s17_calc_ok.pas" > "$tmp/ok/calc.pas"
sed '1,2d;s/^unit s17_release_bad;/unit rel;/' "$root/tests/lint/s17_release_bad.pas" > "$tmp/bad/rel.pas"
fail=0
if "$root/tools/bp" build -Fu"$root/tools/spikes/region" -FE"$tmp/ok" "$tmp/ok/calc.pas" > "$tmp/ok.log" 2>&1 \
    && "$tmp/ok/calc" | grep -q '^5 line(s), 0 error(s)$'; then
  echo "ok   bp build: the calculator is checked, built and runs ($(grep '^bp: checked' "$tmp/ok.log"))"
else
  echo "FAIL bp build of the calculator:"; cat "$tmp/ok.log"; fail=1
fi
if "$root/tools/bp" build -Fu"$root/tools/spikes/region" -FE"$tmp/bad" "$tmp/bad/rel.pas" > "$tmp/bad.log" 2>&1 \
    || [ -e "$tmp/bad/rel.o" ]; then
  echo "FAIL bp build built a unit with a use after Release:"; cat "$tmp/bad.log"; fail=1
else
  grep -q 'SAFE-S17' "$tmp/bad.log" && echo "ok   bp build: a use after Release is not built" \
    || { echo "FAIL bp build: no S17 finding:"; cat "$tmp/bad.log"; fail=1; }
fi
exit $fail
