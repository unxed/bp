#!/bin/sh
# Separation tv/ vs fpide/ (same rules as unxed/dn tools/check-layout.sh, simplified).
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
. "$here/tools/need-tv.sh"
fail=0
err() { echo "fpide-layout: $*" >&2; fail=1; }

own=$(ls tv/src/*.pas 2>/dev/null | sed 's|.*/||; s|\.pas$||' | tr 'A-Z' 'a-z' | sort -u | tr '\n' ' ')
allowed="system sysutils dos go32 objpas math strings classes baseunix unix termio typinfo variants windows process"
for f in tv/src/*.pas; do
    [ -f "$f" ] || continue
    units=$(awk 'BEGIN{IGNORECASE=1} /^[ \t]*uses[ \t]*$|^[ \t]*uses[ \t]/{u=1} u{print} u&&/;/{u=0}' "$f" \
        | sed 's/{[^}]*}//g; s/(\*.*\*)//g; s/^[ \t]*uses//I' | tr ',;' '\n\n' | tr -d ' \t\r' \
        | tr 'A-Z' 'a-z' | grep -v '^$' | sort -u)
    for u in $units; do
        case " $own $allowed " in *" $u "*) ;; *) err "$f uses '$u' outside tv/ or RTL";; esac
    done
done

if grep -rIl --include='*.pas' --include='*.inc' -E 'fpide/|Text Mode IDE port' tv/src 2>/dev/null | grep .; then
    err "tv/ mentions fpide"
fi

if ls src/views.pas src/app.pas 2>/dev/null; then
    err "src must not contain FV unit files copied from packages/fv (use shims)"
fi

exit $fail
