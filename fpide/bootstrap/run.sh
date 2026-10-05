#!/bin/sh
# Reproduce fpide/src (packages/ide) and fpide/fpc-compiler (compiler/)
# from upstream FPC at the pin in upstream.env.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
. "$here/upstream.env"
out=${1:-$root/build/bootstrap-fpide}
tmp=$out/_fpc
ide=$out/staging-ide
comp=$out/staging-compiler
rm -rf "$ide" "$comp"
mkdir -p "$ide" "$comp"
"$here/fetch.sh" "$tmp"

copy_tree() {
    src=$1
    dest=$2
    [ -d "$src" ] || { echo "missing $src" >&2; exit 1; }
    ( cd "$src" && find . -type f ! -path './fpmake*' ! -name 'fpmake.exe' ! -name '*.o' ! -name '*.ppu' ! -name '*.a' ) | while read -r f; do
        base=$(echo "$f" | sed 's|^\./||')
        # Skip VCS / build debris if any
        case "$base" in
            .git/*|*/.git/*) continue ;;
        esac
        outf="$dest/$(echo "$base" | tr 'A-Z' 'a-z')"
        mkdir -p "$(dirname "$outf")"
        cp "$src/$base" "$outf"
    done
}

copy_tree "$tmp/$FPC_IDE_PATH" "$ide"
copy_tree "$tmp/compiler" "$comp"
echo "staging-ide: $ide ($(find "$ide" -type f | wc -l) files)"
echo "staging-compiler: $comp ($(find "$comp" -type f | wc -l) files)"
