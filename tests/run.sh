#!/bin/sh
# Runs inside a bare distribution image with dist/ mounted at /dist: the probe with the
# package, then without it, which must fail, so the package is what it found.
#   tests/run.sh valle-lavapipe-0.1.0-linux-x86_64
L=/dist/$1/lib
echo "### $(. /etc/os-release && echo "$PRETTY_NAME")"
(ldd --version 2>&1 || true) | sed -n 1p
echo "--- with the package"
LD_LIBRARY_PATH="$L" VK_DRIVER_FILES="$L/lvp_icd.x86_64.json" /dist/probe
with=$?
echo "--- without it"
/dist/probe
without=$?
[ "$with" -eq 0 ] && [ "$without" -ne 0 ]
