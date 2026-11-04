#!/usr/bin/env bash
# Puts a patched pasresolver.pp into OUT: tools/bpvet/resolver/get.sh OUT
# The source is the file of FPC 3.2.2: from the FPC sources installed on this machine (FPCSRC, default
# /usr/share/fpcsrc/3.2.2; Debian, Ubuntu: fpc-source-3.2.2), else from the FPC repository by the release tag.
# The file is accepted only with the expected SHA-256; then pasresolver.patch is applied.
set -eu
out=$1
here=$(cd "$(dirname "$0")" && pwd)
sha=aa3ea4ed76028329d6dc4cff6b0ceef070070ce3341552d8d82ac73d0f05a2eb
src=${FPCSRC:-/usr/share/fpcsrc/3.2.2}/packages/fcl-passrc/src/pasresolver.pp
url=https://gitlab.com/freepascal.org/fpc/source/-/raw/release_3_2_2/packages/fcl-passrc/src/pasresolver.pp
mkdir -p "$out"
if [ -f "$src" ] && echo "$sha  $src" | sha256sum -c --status; then
  cp "$src" "$out/pasresolver.pp"
else
  curl -fsSL -o "$out/pasresolver.pp" "$url"
  echo "$sha  $out/pasresolver.pp" | sha256sum -c --status || { echo "get.sh: unexpected pasresolver.pp from $url" >&2; exit 1; }
fi
patch -s -d "$out" -p4 < "$here/pasresolver.patch"
echo "get.sh: $out/pasresolver.pp (FPC 3.2.2 + pasresolver.patch)"
