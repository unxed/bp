#!/bin/sh
# Download FPC packages/ide at the pinned tag (see upstream.env).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/upstream.env"
work=${1:?usage: fetch.sh WORK_DIR}
mkdir -p "$work"
if [ -d "$work/.git" ]; then
    git -C "$work" fetch --depth 1 origin tag "$FPC_TAG" 2>/dev/null || git -C "$work" fetch --depth 1 origin "$FPC_COMMIT"
    git -C "$work" checkout -f "$FPC_COMMIT"
else
    git clone --depth 1 --branch "$FPC_TAG" "$FPC_REPO" "$work" 2>/dev/null ||
        git clone --depth 1 "$FPC_REPO" "$work" && git -C "$work" checkout -f "$FPC_COMMIT"
fi
echo "FPC at $(git -C "$work" rev-parse HEAD)"
