#!/bin/bash
# Installs Debian packages on a CI runner and fails fast when a mirror stalls. The download is the part that can stall, so
# it runs apart from the unpacking: each download run is limited to CI_APT_SECONDS (45 by default; a stalled connection to
# 15 seconds), a failed try is repeated, 3 tries in all, and dpkg is repaired before a retry (an interrupted install leaves
# it with "dpkg was interrupted", and every later apt-get fails on that). The unpacking runs from the local cache and gets
# 10 minutes: it does not depend on the network. A normal install takes 10-20 s; wine (about 90 packages) about a minute.
# usage: [CI_APT_SECONDS=150] tools/ci-apt.sh PACKAGE...
set -u
limit=${CI_APT_SECONDS:-45}
opts=(-o Acquire::Retries=2 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15 -o DPkg::Lock::Timeout=60)
for try in 1 2 3; do
  if sudo timeout "$limit" apt-get "${opts[@]}" update -q \
    && sudo DEBIAN_FRONTEND=noninteractive timeout "$limit" apt-get "${opts[@]}" install -y -q --download-only "$@" \
    && sudo DEBIAN_FRONTEND=noninteractive timeout 600 apt-get "${opts[@]}" install -y -q --no-download "$@"; then
    exit 0
  fi
  echo "ci-apt: try $try failed" >&2
  sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a > /dev/null 2>&1 || true
  sleep 5
done
echo "ci-apt: cannot install $*" >&2
exit 1
