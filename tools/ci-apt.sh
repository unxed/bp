#!/bin/bash
# Installs Debian packages on a CI runner. A failed apt-get run is repeated, 3 tries in all, and dpkg is repaired before a
# retry (an interrupted install leaves it with "dpkg was interrupted", and every later apt-get fails on that). There is
# no time limit of its own: a slow mirror waits, it does not fail (the owner's rule, 2026-11-04).
# usage: tools/ci-apt.sh PACKAGE...
set -u
opts=(-o Acquire::Retries=3 -o DPkg::Lock::Timeout=300)
for try in 1 2 3; do
  if sudo apt-get "${opts[@]}" update -q \
    && sudo DEBIAN_FRONTEND=noninteractive apt-get "${opts[@]}" install -y -q "$@"; then
    exit 0
  fi
  echo "ci-apt: try $try failed" >&2
  sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a > /dev/null 2>&1 || true
  sleep 10
done
echo "ci-apt: cannot install $*" >&2
exit 1
