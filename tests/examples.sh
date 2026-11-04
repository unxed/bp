#!/usr/bin/env bash
# The examples (examples/), built with tools/bp build and run as a user would run them.
#   examples/httpd: static without libc; the three routes, a 404, a 400 on garbage, a body with Content-Length and a
#   pipelined request on one connection; then SIGTERM: it must print "no leaks" and exit with 0.
# usage: tests/examples.sh      (needs curl, readelf, and ppudump of fp-utils for the stubs of tools/bp)
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
pid=
trap '[ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; rm -rf "$tmp"' EXIT
fail=0
check() {   # check WHAT GOT EXPECTED
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2], expected [$3]"; fail=1; fi
}

"$root/tools/bp" build -Fu"$root/tools/spikes/region" -FE"$tmp" "$root/examples/httpd/httpd.pas" > "$tmp/build.log" 2>&1 \
  || { cat "$tmp/build.log"; exit 1; }
grep '^bp: checked' "$tmp/build.log"
if readelf -lW "$tmp/httpd" | grep -q INTERP || readelf -dW "$tmp/httpd" | grep -q NEEDED; then
  echo "FAIL httpd is dynamic"; fail=1
else
  echo "ok   httpd: static, no libc"
fi

port=${PORT:-18080}
url=http://127.0.0.1:$port
"$tmp/httpd" "$port" > "$tmp/run.log" 2>&1 &
pid=$!
for _ in $(seq 100); do curl -s -o /dev/null "$url/" && break; sleep 0.1; done
check "GET /" "$(curl -s "$url/")" "Hello from Better Pascal"
check "GET /json?n=5" "$(curl -s "$url/json?n=5")" '{"n":5,"squares":[1,4,9,16,25]}'
check "GET /json (n=10 by default)" "$(curl -s "$url/json")" '{"n":10,"squares":[1,4,9,16,25,36,49,64,81,100]}'
check "GET /json?n=1001 is 400" "$(curl -s -o /dev/null -w '%{http_code}' "$url/json?n=1001")" 400
check "GET /nope is 404" "$(curl -s -o /dev/null -w '%{http_code}' "$url/nope")" 404
stats=$(curl -s "$url/stats")
if [[ $stats =~ ^\{\"requests\":[1-9][0-9]*,\"bytes\":[1-9][0-9]*\}$ ]]; then echo "ok   GET /stats: $stats"
else echo "FAIL GET /stats: $stats"; fail=1; fi
exec 3<> "/dev/tcp/127.0.0.1/$port"
printf 'GARBAGE\r\n\r\n' >&3
check "garbage is 400 and closes" "$(timeout 5 cat <&3 | head -n 1 | tr -d '\r')" "HTTP/1.1 400 Bad Request"
exec 3<&-
exec 3<> "/dev/tcp/127.0.0.1/$port"
printf 'POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloGET /nope HTTP/1.1\r\nConnection: close\r\n\r\n' >&3
check "a body, then a pipelined request with Connection: close" \
  "$(timeout 5 cat <&3 | grep '^HTTP/' | tr -d '\r' | tr '\n' ' ')" "HTTP/1.1 200 OK HTTP/1.1 404 Not Found "
exec 3<&-

kill -TERM "$pid"
code=0
timeout 10 tail --pid="$pid" -f /dev/null || code=timeout
wait "$pid" || code=$?
pid=
check "SIGTERM: exit code" "$code" 0
check "SIGTERM: no leaks" "$(tail -n 1 "$tmp/run.log")" "no leaks"
[ $fail = 0 ] || cat "$tmp/run.log"
exit $fail
