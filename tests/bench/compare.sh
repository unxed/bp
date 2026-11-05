#!/usr/bin/env bash
# The benchmark suite of Better Pascal against C, Rust, Go and Goose (safe/SPEC.md §25.2; report only, no thresholds).
# Four programs, each written the same way in each language (tests/bench/suite/NAME/NAME.{pas,c,rs,go,goose}): binary trees
# (allocation), n-body (floating point), fannkuch (integers and arrays), a word count (strings). Every program prints
# one line, a checksum, and the script checks that all languages print the same line.
# Builds (release, same machine):  Bp: tools/bp build --release -O2     C: gcc -O2 and clang -O2
#                                  Rust: rustc -O                      Go: go build
#                                  Goose: goose build -O2 (the default of a build: no --debug checks)
# Each binary is run RUNS times; the cell is the median wall time and the ratio to C (gcc). The output is a Markdown
# table with the machine and the compiler versions. A missing toolchain makes its column "n/a".
# usage: tests/bench/compare.sh [out-dir]
# environment: RUNS (5)   LANGS ("bp gcc clang rust go goose")   PROGS ("bintrees nbody fannkuch wordcount")
#              WORDS (4000000: the length of the text of the word count)   FPC (fpc)
#              GOOSE (goose on PATH, else ~/.local/opt/goose-v2026.3/goose: the Goose compiler)
# The exit code is 1 when a build fails or the checksums differ; a missing toolchain is not a failure.
set -u
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
suite=$here/suite
out=${1:-$(mktemp -d)}
RUNS=${RUNS:-5}
LANGS=${LANGS:-"bp gcc clang rust go goose"}
PROGS=${PROGS:-"bintrees nbody fannkuch wordcount"}
WORDS=${WORDS:-4000000}
FPC=${FPC:-fpc}
if [ -z "${GOOSE:-}" ]; then
  if command -v goose > /dev/null 2>&1; then GOOSE=goose; else GOOSE=$HOME/.local/opt/goose-v2026.3/goose; fi
fi
mkdir -p "$out"
failed=0

declare -A title=([bp]="Bp" [gcc]="C (gcc -O2)" [clang]="C (clang -O2)" [rust]="Rust (rustc -O)" [go]="Go" [goose]="Goose (build -O2)" )
declare -A time_us samples ver ok

have() { command -v "$1" > /dev/null 2>&1; }

avail() {
  case $1 in
    bp) have "$FPC" && have python3 && { have ppudump-3.2.2 || have ppudump; } ;;
    gcc) have gcc ;;
    clang) have clang ;;
    rust) have rustc ;;
    go) have go ;;
    goose) have "$GOOSE" && have gcc ;;
    *) return 1 ;;
  esac
}

first_line() { "$@" 2>&1 | head -n 1; }

version() {
  case $1 in
    bp) echo "fpc $("$FPC" -iV) (tools/bp build --release -O2)" ;;
    gcc) first_line gcc --version ;;
    clang) first_line clang --version ;;
    rust) first_line rustc --version ;;
    go) first_line go version ;;
    goose) echo "$(first_line "$GOOSE" version) (goose build -O2, over gcc)" ;;
  esac
}

# build LANG PROG: the binary is $out/PROG/LANG
build() {
  local l=$1 p=$2 d=$out/$2 src=$suite/$2/$2 extra=()
  mkdir -p "$d/obj-$l"
  case $l in
    bp)
      [ "$p" = bintrees ] && extra=(-Fu"$root/tools/spikes/region")   # the region style: the spike unit Region
      "$root/tools/bp" build --release -O2 ${extra[@]+"${extra[@]}"} -FU"$d/obj-$l" -FE"$d/obj-$l" "$src.pas" \
        > "$d/build-$l.log" 2>&1 && mv "$d/obj-$l/$p" "$d/$l" ;;
    gcc) gcc -O2 -o "$d/$l" "$src.c" -lm > "$d/build-$l.log" 2>&1 ;;
    clang) clang -O2 -o "$d/$l" "$src.c" -lm > "$d/build-$l.log" 2>&1 ;;
    rust) rustc -O -o "$d/$l" "$src.rs" > "$d/build-$l.log" 2>&1 ;;
    go) go build -o "$d/$l" "$src.go" > "$d/build-$l.log" 2>&1 ;;
    goose) GOOSE_CC=gcc "$GOOSE" build -O2 -o "$d/$l" "$src.goose" > "$d/build-$l.log" 2>&1 ;;
  esac
}

now_us() { local t=$EPOCHREALTIME; echo "${t/./}"; }

# once LANG PROG: one timed run; appends the microseconds to samples[PROG,LANG]; ok[PROG,LANG] is the printed line
once() {
  local l=$1 p=$2 d=$out/$2 args=() t0 t1
  [ "$p" = wordcount ] && args=("$out/text.txt")
  t0=$(now_us)
  "$d/$l" ${args[@]+"${args[@]}"} > "$d/out-$l.txt" 2> "$d/err-$l.txt" || { ok[$p,$l]="exit code $?"; return 1; }
  t1=$(now_us)
  samples[$p,$l]+=" $((t1 - t0))"
  ok[$p,$l]=$(head -n 1 "$d/out-$l.txt")
}

# the median of the samples of PROG,LANG, in microseconds
median() { printf '%s\n' ${samples[$1,$2]} | sort -n | sed -n "$((RUNS / 2 + 1))p"; }

# seconds with three decimals from microseconds
secs() { printf '%d.%03d' $(($1 / 1000000)) $(($1 % 1000000 / 1000)); }

active=()
for l in $LANGS; do
  if avail "$l"; then active+=("$l"); ver[$l]=$(version "$l"); else ver[$l]="not available"; fi
done

echo "== build" >&2
for p in $PROGS; do
  [ "$p" = wordcount ] && ! have awk && continue
  for l in ${active[@]+"${active[@]}"}; do
    if build "$l" "$p"; then ok[$p,$l]=built; else
      echo "build of $p ($l) failed; see $out/$p/build-$l.log" >&2
      sed 's/^/    /' "$out/$p/build-$l.log" | tail -n 15 >&2
      ok[$p,$l]=failed
      failed=1
    fi
  done
done

if [[ " $PROGS " == *" wordcount "* ]] && have awk; then
  echo "== text of the word count ($WORDS words)" >&2
  [ -s "$out/text.txt" ] && [ "$(cat "$out/text.words" 2> /dev/null)" = "$WORDS" ] \
    || { awk -v words="$WORDS" -f "$suite/wordcount/gen.awk" > "$out/text.txt" && echo "$WORDS" > "$out/text.words"; }
fi

# the runs of the languages alternate (round after round), so that a disturbance of the machine falls on all of them
echo "== run ($RUNS rounds)" >&2
for p in $PROGS; do
  echo "   $p" >&2
  built=()
  for l in ${active[@]+"${active[@]}"}; do [ "${ok[$p,$l]:-}" = built ] && built+=("$l"); done
  for ((i = 0; i < RUNS; i++)); do
    for l in ${built[@]+"${built[@]}"}; do
      [ "${ok[$p,$l]}" != failed ] || continue
      once "$l" "$p" || { echo "run of $p ($l) failed: ${ok[$p,$l]}" >&2; failed=1; ok[$p,$l]=failed; }
    done
  done
  for l in ${built[@]+"${built[@]}"}; do
    [ "${ok[$p,$l]}" != failed ] && time_us[$p,$l]=$(median "$p" "$l")
  done
done

# the checksums: every language prints the line of the first one that built
declare -A bad
for p in $PROGS; do
  ref=
  for l in ${active[@]+"${active[@]}"}; do
    [ -n "${time_us[$p,$l]:-}" ] || continue
    if [ -z "$ref" ]; then ref=${ok[$p,$l]}; continue; fi
    if [ "${ok[$p,$l]}" != "$ref" ]; then
      bad[$p,$l]=1
      failed=1
      echo "CHECKSUM MISMATCH $p: $l printed [${ok[$p,$l]}], expected [$ref]" >&2
    fi
  done
done

cpu=$(grep -m1 'model name' /proc/cpuinfo 2> /dev/null | sed 's/^[^:]*: *//')
echo
echo "Machine: ${cpu:-unknown CPU}, $(nproc 2> /dev/null || echo '?') logical CPUs, $(uname -sr)"
echo
echo "Compilers:"
echo
for l in $LANGS; do echo "- ${title[$l]:-$l}: ${ver[$l]}"; done
echo
echo "Median wall time of $RUNS runs, in seconds, and the ratio to C (gcc -O2); lower is better."
echo
row="| program |"
sep="|---|"
for l in $LANGS; do row+=" ${title[$l]:-$l} |"; sep+="---|"; done
echo "$row"
echo "$sep"
for p in $PROGS; do
  row="| $p |"
  for l in $LANGS; do
    t=${time_us[$p,$l]:-}
    if [ -z "$t" ]; then
      if [ "${ok[$p,$l]:-}" = failed ]; then cell="failed"; else cell="n/a"; fi
    else
      cell="$(secs "$t") s"
      g=${time_us[$p,gcc]:-}
      if [ -n "$g" ] && [ "$g" -gt 0 ]; then
        r=$((t * 100 / g))
        cell+=" ($((r / 100)).$(printf '%02d' $((r % 100)))x)"
      fi
      [ -z "${bad[$p,$l]:-}" ] || cell+=" WRONG OUTPUT"
    fi
    row+=" $cell |"
  done
  echo "$row"
done
echo
for p in $PROGS; do
  for l in $LANGS; do
    [ -z "${ok[$p,$l]:-}" ] || [ -z "${time_us[$p,$l]:-}" ] || { echo "Output of $p: ${ok[$p,$l]}"; break; }
  done
done
exit $failed
