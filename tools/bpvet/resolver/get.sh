#!/usr/bin/env bash
# Puts the patched pastree.pp, pparser.pp and pasresolver.pp of fcl-passrc into OUT, with fcl-passrc.inc they include
# and pasresolveeval.pas (unchanged; it is built again since it uses PasTree): tools/bpvet/resolver/get.sh OUT
# The sources are the files of FPC 3.2.2: from the FPC sources installed on this machine (FPCSRC, default
# /usr/share/fpcsrc/3.2.2; Debian, Ubuntu: fpc-source-3.2.2), else from the FPC repository by the release tag.
# A file is accepted only with the expected SHA-256; then the patches *.patch of this directory are applied.
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
fetch pastree.pp 2060e1555766c5f3fe2e984288c4bf748df9a139186e74ff866112ee2277ed0a
fetch pasresolveeval.pas 9eff9853b819ac9b4408fd7099707878dcc3f4fdaf2589e1779efc5cd205f638
fetch pparser.pp 4b98255d5bee3df1a2aa3063d41c72b8f7aa6d4a66c7b3a33676eab9f8074854
fetch fcl-passrc.inc fd82c3a50b85517cd302e89ec3d24f3eb60a29c34c6eba61d83f4a9e6118357a
for p in pastree pparser pasresolver; do
  patch -s -d "$out" -p4 < "$here/$p.patch"
done
echo "get.sh: $out: pastree.pp, pparser.pp, pasresolver.pp of FPC 3.2.2 with the patches"
