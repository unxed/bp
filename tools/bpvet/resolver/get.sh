#!/usr/bin/env bash
# Puts the patched pasresolver.pp and pparser.pp (and the fcl-passrc.inc they include) into OUT: tools/bpvet/resolver/get.sh OUT
# The sources are the files of FPC 3.2.2: from the FPC sources installed on this machine (FPCSRC, default
# /usr/share/fpcsrc/3.2.2; Debian, Ubuntu: fpc-source-3.2.2), else from the FPC repository by the release tag.
# A file is accepted only with the expected SHA-256; then pasresolver.patch and pparser.patch are applied.
set -eu
out=$1
here=$(cd "$(dirname "$0")" && pwd)
dir=packages/fcl-passrc/src
mkdir -p "$out"
fetch() { # NAME SHA256
  local src=${FPCSRC:-/usr/share/fpcsrc/3.2.2}/$dir/$1
  local url=https://gitlab.com/freepascal.org/fpc/source/-/raw/release_3_2_2/$dir/$1
  if [ -f "$src" ] && echo "$2  $src" | sha256sum -c --status; then
    cp "$src" "$out/$1"
  else
    curl -fsSL -o "$out/$1" "$url"
    echo "$2  $out/$1" | sha256sum -c --status || { echo "get.sh: unexpected $1 from $url" >&2; exit 1; }
  fi
}
fetch pasresolver.pp aa3ea4ed76028329d6dc4cff6b0ceef070070ce3341552d8d82ac73d0f05a2eb
fetch pparser.pp 4b98255d5bee3df1a2aa3063d41c72b8f7aa6d4a66c7b3a33676eab9f8074854
fetch fcl-passrc.inc fd82c3a50b85517cd302e89ec3d24f3eb60a29c34c6eba61d83f4a9e6118357a
patch -s -d "$out" -p4 < "$here/pasresolver.patch"
patch -s -d "$out" -p4 < "$here/pparser.patch"
echo "get.sh: $out/pasresolver.pp, $out/pparser.pp (FPC 3.2.2 + the patches)"
