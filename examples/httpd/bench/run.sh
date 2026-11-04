#!/usr/bin/env bash
# The benchmark of examples/httpd (report only, no thresholds, like tests/bench/run.sh): the server of Better Pascal
# against the same server in Go (net/http, main.go) and in Rust (the standard library, a thread per connection,
# main.rs). Each runs on a port of its own under /usr/bin/time -v, is warmed up, then loaded on /, /json?n=100 and
# /stats with wrk when it is on PATH (-c C for D seconds), else with ab -k -c C -n N; prints one Markdown table.
# usage: examples/httpd/bench/run.sh [out-dir]
#   needs fpc and ppudump (fp-utils), go, rustc, ab (apache2-utils) or wrk, /usr/bin/time;
#   environment: N (default 100000), C (64), D (10), PORT (the first of three, default 18090)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
out=${1:-$(mktemp -d)}
N=${N:-100000} C=${C:-64} D=${D:-10} PORT=${PORT:-18090}
mkdir -p "$out"
timers=()
trap 'for t in "${timers[@]}"; do pkill -KILL -P "$t" 2>/dev/null || true; done' EXIT

echo "== build"
"$root/tools/bp" build --release -Fu"$root/tools/spikes/region" -FU"$out" -o"$out/httpd-bp" \
  "$root/examples/httpd/httpd.pas" > "$out/build-bp.log" 2>&1 || { cat "$out/build-bp.log"; exit 1; }
(cd "$here" && go build -o "$out/httpd-go" main.go)
rustc -O -C target-cpu=native -o "$out/httpd-rust" "$here/main.rs"
fpc -iV | sed 's/^/fpc /'; go version; rustc --version; nproc | sed 's/$/ CPUs/'
if command -v wrk > /dev/null; then tool=wrk; else tool=ab; fi

# load URL: prints "requests/s mean-latency-ms"
load() {
  local log
  if [ $tool = wrk ]; then
    log=$(wrk -t "$(nproc)" -c "$C" -d "${D}s" "$1" 2>&1) || true
    echo "$log" >> "$out/load.log"
    echo "$log" | awk '/Requests\/sec:/ { rps = $2 }
      /^ *Latency/ { v = $2; u = v; sub(/[0-9.]+/, "", u); sub(/[a-z]+$/, "", v)
        ms = (u == "us") ? v / 1000 : (u == "s") ? v * 1000 : v }
      END { if (rps == "") print "error error"; else printf "%.0f %.2f\n", rps, ms }'
  else
    log=$(ab -k -q -c "$C" -n "$N" "$1" 2>&1) || true
    echo "$log" >> "$out/load.log"
    echo "$log" | awk '/^Requests per second:/ { rps = $4 } /^Time per request:/ && ms == "" { ms = $4 }
      END { if (rps == "") print "error error"; else printf "%.0f %.2f\n", rps, ms }'
  fi
}

rows=()
port=$PORT
for name in bp go rust; do
  echo "== $name on port $port"
  /usr/bin/time -v -o "$out/$name.time" "$out/httpd-$name" "$port" > "$out/$name.log" 2>&1 &
  timer=$!
  timers+=("$timer")
  for _ in $(seq 100); do curl -s -o /dev/null "http://127.0.0.1:$port/" && break; sleep 0.1; done
  if [ $tool = wrk ]; then wrk -t 2 -c 8 -d 2s "http://127.0.0.1:$port/" > /dev/null 2>&1 || true
  else ab -k -q -c 8 -n 5000 "http://127.0.0.1:$port/" > /dev/null 2>&1 || true; fi
  results=()
  for path in / '/json?n=100' /stats; do
    r=$(load "http://127.0.0.1:$port$path")
    echo "$path: $r"
    results+=("$path $r")
  done
  pkill -TERM -P "$timer" || true
  wait "$timer" || true
  rss=$(awk -F': ' '/Maximum resident set size/ { print $2 }' "$out/$name.time")
  size=$(stat -c %s "$out/httpd-$name")
  for r in "${results[@]}"; do
    set -- $r
    rows+=("| $name | \`$1\` | $2 | $3 | $size | ${rss:-?} |")
  done
  port=$((port + 1))
done

echo
echo "Load: $tool, $C connections ($( [ $tool = wrk ] && echo "${D} s" || echo "$N requests, keep-alive" )), $(nproc) CPUs"
echo
echo "| Server | Route | Requests/s | Mean latency, ms | Binary, bytes | Peak RSS, KiB |"
echo "|---|---|---|---|---|---|"
printf '%s\n' "${rows[@]}"
