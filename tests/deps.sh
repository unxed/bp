#!/usr/bin/env bash
# tools/bp get, vendor and build with a deps.lock (safe/SPEC.md §15), over local git repositories: a library a (unit
# acme.str: Shout at v1.0.0, Whisper added at v1.1.0), a library b (unit bob.greet in src/) that requires a v1.0.0, an
# application that requires a v1.1.0 and b v1.0.0. Checked: MVS selects a v1.1.0; the program builds and runs; a second
# get changes nothing; vendor/ builds with a cache that has no module; a moved tag stops get; a mirror line is used
# when the first URL does not answer. Needs git; ppudump (fp-utils) for the stubs, as tests/bp.sh.
# usage: tests/deps.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp"; rm -rf "$tmp"' EXIT
export BP_CACHE=$tmp/cache
bp=$root/tools/bp
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; [ -z "${2:-}" ] || cat "$2"; fail=1; }

# repo DIR: a git repository with a local identity
repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.com
}
commit() { git -C "$1" add -A && git -C "$1" commit -qm "$2" && git -C "$1" tag "$3"; }

unit() { # FILE NAME USES INTERFACE IMPLEMENTATION
  printf 'unit %s;\n\n{$mode objfpc}{$H+}\n\ninterface\n\nuses\n  %sBP;\n\n%s\n\nimplementation\n\n%s\n\nend.\n' \
    "$2" "$3" "$4" "$5" > "$1"
}

a=$tmp/a b=$tmp/b app=$tmp/app
repo "$a"
printf 'module %s\nsafe 0.6\n' "$a" > "$a/deps.txt"
unit "$a/acme.str.pas" acme.str 'SysUtils, ' 'function Shout(const S: String): String;' \
  "function Shout(const S: String): String;
begin
  Result := UpperCase(S) + '!';
end;"
commit "$a" one v1.0.0
unit "$a/acme.str.pas" acme.str 'SysUtils, ' 'function Shout(const S: String): String;
function Whisper(const S: String): String;' \
  "function Shout(const S: String): String;
begin
  Result := UpperCase(S) + '!';
end;

function Whisper(const S: String): String;
begin
  Result := LowerCase(S) + '...';
end;"
commit "$a" two v1.1.0

repo "$b"
mkdir -p "$b/src"
printf 'module %s\nsafe 0.6\nrequire %s v1.0.0\n' "$b" "$a" > "$b/deps.txt"
unit "$b/src/bob.greet.pas" bob.greet 'acme.str, ' 'function Greet(const Name: String): String;' \
  "function Greet(const Name: String): String;
begin
  Result := 'Hello, ' + Shout(Name);
end;"
commit "$b" one v1.0.0

mkdir -p "$app"
printf '// the application\nsafe 0.6\nrequire %s v1.1.0  // Whisper\nrequire %s v1.0.0\n' "$a" "$b" > "$app/deps.txt"
printf 'program app;\n\n{$mode objfpc}{$H+}\n\n// UNSAFE: BP goes first for the thread manager (SPEC §14); the units after it declare no unsafe primitive\nuses\n  BP, acme.str, bob.greet;\n\nbegin\n  WriteLn(Greet(%s), %s, Whisper(%s));\nend.\n' \
  "'world'" "' '" "'QUIET'" > "$app/app.pas"
want='Hello, WORLD! quiet...'
ca=$(git -C "$a" rev-parse v1.1.0) cb=$(git -C "$b" rev-parse v1.0.0)

t0=$(date +%s%N)
if "$bp" get "$app" > "$tmp/get1.log" 2>&1 \
    && [ "$(cat "$app/deps.lock")" = "$(printf '%s v1.1.0 %s\n%s v1.0.0 %s' "$a" "$ca" "$b" "$cb")" ]; then
  ok "bp get: MVS selects a v1.1.0 (the greatest required) and b v1.0.0; deps.lock records their commits"
else
  bad "bp get did not write the expected deps.lock:" "$tmp/get1.log"; cat "$app/deps.lock" 2>/dev/null
fi
if "$bp" build -FE"$app" "$app/app.pas" > "$tmp/build1.log" 2>&1 && [ "$("$app/app")" = "$want" ]; then
  ok "bp build: the units of a and b come from the module cache; the program prints \"$want\""
else
  bad "bp build with deps.lock:" "$tmp/build1.log"
fi
cp "$app/deps.lock" "$tmp/lock1"
if "$bp" get "$app" > "$tmp/get2.log" 2>&1 && [ "$(grep -c '(cached)$' "$tmp/get2.log")" = 2 ] \
    && cmp -s "$app/deps.lock" "$tmp/lock1"; then
  ok "bp get again: both modules (cached), deps.lock unchanged"
else
  bad "the second bp get:" "$tmp/get2.log"
fi

# vendor/, then a cache with no module (only the tools, to save their build) and the repositories out of reach
if "$bp" vendor "$app" > "$tmp/vendor.log" 2>&1 && [ -f "$app/vendor/${a#/}/acme.str.pas" ] \
    && [ -f "$app/vendor/${b#/}/src/bob.greet.pas" ] && cmp -s "$app/vendor/modules.txt" "$app/deps.lock"; then
  ok "bp vendor: vendor/<path>/ and vendor/modules.txt"
else
  bad "bp vendor:" "$tmp/vendor.log"
fi
mkdir -p "$tmp/empty"
cp "$BP_CACHE"/bpvet-* "$BP_CACHE"/bpget-* "$tmp/empty/"
mv "$a" "$tmp/a.away"
mv "$b" "$tmp/b.away"
rm -f "$app/app"
if BP_CACHE=$tmp/empty "$bp" build -FE"$app" "$app/app.pas" > "$tmp/build2.log" 2>&1 \
    && [ "$("$app/app")" = "$want" ] && [ ! -e "$tmp/empty/mod" ]; then
  ok "bp build from vendor/: no module in the cache, no repository reachable"
else
  bad "bp build from vendor/:" "$tmp/build2.log"
fi
mv "$tmp/a.away" "$a"
mv "$tmp/b.away" "$b"

# the tag v1.1.0 of a moves to another commit
printf '// moved\n' >> "$a/acme.str.pas"
git -C "$a" commit -qam moved
git -C "$a" tag -f v1.1.0 > /dev/null
if "$bp" get "$app" > "$tmp/get3.log" 2>&1; then
  bad "bp get accepted a moved tag:" "$tmp/get3.log"
elif grep -q "$a v1.1.0: deps.lock records the commit $ca, the tag now points to $(git -C "$a" rev-parse v1.1.0): the tag moved" \
    "$tmp/get3.log" && cmp -s "$app/deps.lock" "$tmp/lock1"; then
  ok "bp get: a moved tag fails, naming the module and both commits; deps.lock unchanged"
else
  bad "bp get on a moved tag: not the expected message:" "$tmp/get3.log"
fi

# a mirror line: the first URL (the directory of a) does not exist, a copy of a answers
cp -R "$a" "$tmp/a.copy"
mv "$a" "$tmp/a.away"
mkdir -p "$tmp/app2" "$tmp/cache2"
cp "$BP_CACHE"/bpget-* "$tmp/cache2/"
printf 'require %s v1.0.0\nmirror %s %s\n' "$a" "$a" "$tmp/a.copy" > "$tmp/app2/deps.txt"
if BP_CACHE=$tmp/cache2 "$bp" get "$tmp/app2" > "$tmp/get4.log" 2>&1 \
    && grep -q "^$a v1.0.0 $(git -C "$tmp/a.copy" rev-parse v1.0.0) (from $tmp/a.copy)$" "$tmp/get4.log"; then
  ok "bp get: the mirror line is used when the first URL does not answer"
else
  bad "bp get with a mirror line:" "$tmp/get4.log"
fi
mv "$tmp/a.away" "$a"

# bpget itself is a program of the dialect: it passes bp build (bpvet --strict --typed)
mkdir -p "$tmp/bpget"
if "$bp" build -FE"$tmp/bpget" -FU"$tmp/bpget" "$root/tools/bpget/bpget.pas" > "$tmp/bpget.log" 2>&1; then
  ok "bp build tools/bpget/bpget.pas ($(grep '^bp: checked' "$tmp/bpget.log"))"
else
  bad "bp build tools/bpget/bpget.pas:" "$tmp/bpget.log"
fi
echo "deps.sh: $(( ($(date +%s%N) - t0) / 1000000 )) ms"
exit $fail
