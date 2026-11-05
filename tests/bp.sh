#!/usr/bin/env bash
# tools/bp (safe/SPEC.md §16, §22.1): bp fix writes the missing header of a program from its file name (S21); then the
# program in the region style is checked, built and runs; a program with a use after Release is not built; a
# program with uses BP is built (the stubs read bp.pas). bp run: a script with a #! line runs, the second run comes
# from the cache, arguments and the exit code pass, a finding names the line and the file of the script, bp fix keeps
# the #! line; bp run --watch rebuilds on a save and stops the program; bp new makes a project that builds and tests
# itself. Needs ppudump (fp-utils) for the stubs.
# usage: tests/bp.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BP_CACHE=$tmp/cache
mkdir -p "$tmp/ok" "$tmp/bad" "$tmp/bp"
sed '1,2d;/^program s17_calc_ok;$/d' "$root/tests/lint/s17_calc_ok.pas" > "$tmp/ok/calc.pas"
sed '1,2d;s/^unit s17_release_bad;/unit rel;/' "$root/tests/lint/s17_release_bad.pas" > "$tmp/bad/rel.pas"
fail=0
"$root/tools/bp" fix -Fu"$root/tools/spikes/region" "$tmp/ok/calc.pas" > "$tmp/fix.log" 2>&1
if grep -qx 'program calc;' "$tmp/ok/calc.pas"; then
  echo "ok   bp fix: the header comes from the file name"
else
  echo "FAIL bp fix did not write the header:"; cat "$tmp/fix.log"; fail=1
fi
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
printf 'program hello;\n\n{$mode objfpc}{$H+}\n\nuses\n  BP;\n\nbegin\n  WriteLn(CPLength(%s));\nend.\n' "'ab'" \
  > "$tmp/bp/hello.pas"
if "$root/tools/bp" build -FE"$tmp/bp" "$tmp/bp/hello.pas" > "$tmp/bp.log" 2>&1 && [ "$("$tmp/bp/hello")" = 2 ]; then
  echo "ok   bp build: a program with uses BP is checked, built and runs"
else
  echo "FAIL bp build of a program with uses BP:"; cat "$tmp/bp.log"; fail=1
fi

# bp run: a Pascal file with a #! line is a script
mkdir -p "$tmp/run"
cat > "$tmp/run/hello.pas" <<'PAS'
#!/usr/bin/env -S tools/bp run
program hello;

{$mode objfpc}{$H+}

uses
  BP;

begin
  WriteLn('hello ', ParamStr(1), ' ', ParamCount);
  if ParamStr(1) = 'fail' then
    Halt(3);
end.
PAS
chmod +x "$tmp/run/hello.pas"
t0=$(date +%s%N)
"$root/tools/bp" run "$tmp/run/hello.pas" > "$tmp/run1.out" 2> "$tmp/run1.err"; rc=$?
t1=$(date +%s%N)
"$root/tools/bp" run "$tmp/run/hello.pas" x > "$tmp/run2.out" 2> "$tmp/run2.err"
t2=$(date +%s%N)
if [ $rc = 0 ] && [ "$(cat "$tmp/run1.out")" = 'hello  0' ] && grep -q '^bp: checked' "$tmp/run1.err"; then
  echo "ok   bp run: a script with a #! line is checked, built and runs ($(( (t1 - t0) / 1000000 )) ms)"
else
  echo "FAIL bp run of a script (rc=$rc):"; cat "$tmp/run1.out" "$tmp/run1.err"; fail=1
fi
if grep -q '^bp: cached$' "$tmp/run2.err" && ! grep -q '^bp: checked' "$tmp/run2.err" \
    && [ "$(cat "$tmp/run2.out")" = 'hello x 1' ] && [ $((t2 - t1)) -lt $((t1 - t0)) ]; then
  echo "ok   bp run: the second run comes from the cache and passes the arguments ($(( (t2 - t1) / 1000000 )) ms)"
else
  echo "FAIL bp run: the second run was not cached:"; cat "$tmp/run2.out" "$tmp/run2.err"; fail=1
fi
"$root/tools/bp" run "$tmp/run/hello.pas" fail > "$tmp/run3.out" 2>&1; rc=$?
if [ $rc = 3 ] && grep -q '^hello fail 1$' "$tmp/run3.out"; then
  echo "ok   bp run: the exit code of the program is the exit code of bp run"
else
  echo "FAIL bp run: exit code $rc, wanted 3:"; cat "$tmp/run3.out"; fail=1
fi
"$root/tools/bp" run --release "$tmp/run/hello.pas" y > "$tmp/run4.out" 2>&1 || true
grep -q '^hello y 1$' "$tmp/run4.out" && echo "ok   bp run --release" || { echo "FAIL bp run --release:"; cat "$tmp/run4.out"; fail=1; }

# a finding of a script names the script and its own line (the #! line is blank in the copy, not removed)
cat > "$tmp/run/bad.pas" <<'PAS'
#!/usr/bin/env -S tools/bp run
program bad;

{$mode objfpc}{$H+}
Begin
End.
PAS
"$root/tools/bp" run "$tmp/run/bad.pas" > "$tmp/bad2.log" 2>&1; rc=$?
if [ $rc != 0 ] && grep -q "bad.pas(5,1)" "$tmp/bad2.log" && ! grep -q '/script/' "$tmp/bad2.log"; then
  echo "ok   bp run: a finding of a script names the script and the line of the file"
else
  echo "FAIL bp run: finding of a script (rc=$rc):"; cat "$tmp/bad2.log"; fail=1
fi
"$root/tools/bp" fix "$tmp/run/bad.pas" > "$tmp/fix2.log" 2>&1
if [ "$(sed -n 1p "$tmp/run/bad.pas")" = '#!/usr/bin/env -S tools/bp run' ] && sed -n 5p "$tmp/run/bad.pas" | grep -qx 'begin'; then
  echo "ok   bp fix: the #! line of a script stays and the reserved words are lower-cased"
else
  echo "FAIL bp fix of a script:"; cat "$tmp/fix2.log" "$tmp/run/bad.pas"; fail=1
fi

# bp new: a project that builds, runs and tests itself
mkdir -p "$tmp/new" "$tmp/newout"
if (cd "$tmp/new" && "$root/tools/bp" new demo) > "$tmp/new.log" 2>&1 && [ -f "$tmp/new/demo/deps.txt" ] \
    && [ -f "$tmp/new/demo/README.md" ] && [ "$(wc -l < "$tmp/new/demo/README.md")" = 3 ] \
    && "$root/tools/bp" build -FE"$tmp/newout" "$tmp/new/demo/demo.pas" >> "$tmp/new.log" 2>&1 \
    && [ "$("$tmp/newout/demo")" = 'Hello from demo' ] \
    && "$root/tools/bp" run "$tmp/new/demo/tests/test_demo.pas" >> "$tmp/new.log" 2>&1; then
  echo "ok   bp new: the project builds, runs and its test passes"
else
  echo "FAIL bp new:"; cat "$tmp/new.log"; fail=1
fi
if (cd "$tmp/new" && "$root/tools/bp" new demo) > "$tmp/new2.log" 2>&1; then
  echo "FAIL bp new overwrote an existing directory"; fail=1
else
  echo "ok   bp new: an existing directory is refused"
fi

# bp run --watch: a save rebuilds, and the program is stopped before it runs again and when the watch ends
mkdir -p "$tmp/w"
cat > "$tmp/w/watch.pas" <<'PAS'
#!/usr/bin/env -S tools/bp run
program watch;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

begin
  WriteLn('up');
  Flush(Output);
  Sleep(60000);
end.
PAS
"$root/tools/bp" run --watch "$tmp/w/watch.pas" > "$tmp/watch.log" 2>&1 &
wpid=$!
for _ in $(seq 100); do grep -q '^up$' "$tmp/watch.log" && break; sleep 0.1; done
sleep 1
echo '{ saved }' >> "$tmp/w/watch.pas"
for _ in $(seq 50); do [ "$(grep -c '^up$' "$tmp/watch.log")" = 2 ] && break; sleep 0.1; done
if grep -q '^bp: rebuilt in [0-9]* ms$' "$tmp/watch.log" && [ "$(grep -c '^up$' "$tmp/watch.log")" = 2 ]; then
  echo "ok   bp run --watch: a save rebuilds and runs the program again ($(grep '^bp: rebuilt' "$tmp/watch.log"))"
else
  echo "FAIL bp run --watch:"; cat "$tmp/watch.log"; fail=1
fi
kill $wpid 2> /dev/null; wait $wpid 2> /dev/null
sleep 0.3
if pgrep -f "$tmp/cache/run/" > /dev/null; then
  echo "FAIL bp run --watch: the program is still running after the watch ended"; pkill -f "$tmp/cache/run/"; fail=1
else
  echo "ok   bp run --watch: the program is stopped with the watch"
fi
exit $fail
