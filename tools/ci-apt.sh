#!/bin/bash
# Installs Debian packages on a CI runner and fails fast when a mirror stalls: every apt-get run is limited to 2 minutes
# and a stalled connection to 20 seconds; a failed try is repeated, 3 tries in all. A normal install takes 10-20 s.
# usage: tools/ci-apt.sh PACKAGE...
set -u
opts=(-o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o DPkg::Lock::Timeout=60)
for try in 1 2 3; do
  if sudo timeout 120 apt-get "${opts[@]}" update -q \
    && sudo DEBIAN_FRONTEND=noninteractive timeout 120 apt-get "${opts[@]}" install -y -q "$@"; then
    exit 0
  fi
  echo "ci-apt: try $try failed" >&2
  sleep 5
done
echo "ci-apt: cannot install $*" >&2
exit 1
