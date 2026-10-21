#!/usr/bin/env bash
# Lint tests of bpvet (tools/bpvet, safe/SPEC.md §6). Each tests/lint/*.pas says on its first line what bpvet reports:
#   // EXPECT: clean           no finding: exit code 0, with --strict too
#   // EXPECT: error SAFE-Sx   exactly one finding, an Error of rule Sx: exit code 1; with --report a Warning and 0
#   // EXPECT: warn SAFE-Sx    exactly one finding, a Warning of rule Sx: exit code 0; with --strict an Error and 1
# An optional second line // ARGS: <bpvet options> (@lint@ = tests/lint) is passed to every run of the file.
# usage: tests/lint.sh BPVET   (the binary built by tools/bpvet/build.sh)
set -u
bpvet=$1
here=$(cd "$(dirname "$0")" && pwd)
fail=0

# check FILE OPTION CODE SEVERITY RULE: bpvet OPTION FILE exits with CODE and prints exactly one finding
# "FILE(LINE,COL) SEVERITY: RULE ...", or none when SEVERITY is empty
check() {
  local f=$1 opt=$2 code=$3 sev=$4 rule=$5 out got n ok=
  out=$("$bpvet" $opt $args "$f" 2>&1)
  got=$?
  n=$(printf '%s\n' "$out" | grep -c 'SAFE-')
  if [ -z "$sev" ]; then
    [ "$got" = "$code" ] && [ "$n" = 0 ] && ok=1
  else
    [ "$got" = "$code" ] && [ "$n" = 1 ] \
      && printf '%s\n' "$out" | grep -qE "^[^ ]+\([0-9]+,[0-9]+\) $sev: $rule " && ok=1
  fi
  if [ "$ok" = 1 ]; then
    echo "ok   $(basename "$f") ${opt:-default}: exit $got${sev:+, $sev $rule}"
  else
    echo "FAIL $(basename "$f") ${opt:-default}: expected exit $code${sev:+ and one $sev $rule}, got exit $got:"
    printf '%s\n' "$out"
    fail=1
  fi
}

for f in "$here"/lint/*.pas; do
  read -r _ _ kind rule < "$f"
  # an optional second line "// ARGS: ..." gives bpvet options; @lint@ stands for the directory tests/lint
  args=$(sed -n '2s#^// ARGS: ##p' "$f"); args=${args//@lint@/$here/lint}
  case "$kind" in
    clean) check "$f" "" 0 "" ""; check "$f" --strict 0 "" "" ;;
    error) check "$f" "" 1 Error "$rule"; check "$f" --report 0 Warning "$rule" ;;
    warn)  check "$f" "" 0 Warning "$rule"; check "$f" --strict 1 Error "$rule" ;;
    *) echo "FAIL $(basename "$f"): the first line is not // EXPECT: clean|error SAFE-Sx|warn SAFE-Sx"; fail=1 ;;
  esac
done
exit $fail
