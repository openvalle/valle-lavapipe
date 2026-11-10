#!/bin/sh
# Runs inside a bare distribution image with dist/ mounted at /dist: the probe with the
# package, then calling its driver directly, as Valle does, then without it, which must fail,
# so the package is what it found.
#   tests/run.sh valle-lavapipe-0.1.0-linux-x86_64
L=/dist/$1/lib
BUILD_ARCH=$(uname -m)
PROBE=/dist/probe-$BUILD_ARCH
echo "### $(. /etc/os-release && echo "$PRETTY_NAME")"
(ldd --version 2>&1 || true) | sed -n 1p
echo "--- with the package"
LD_LIBRARY_PATH="$L" VK_DRIVER_FILES="$L/lvp_icd.$BUILD_ARCH.json" "$PROBE"
with=$?
echo "--- its driver directly, without the loader"
"$PROBE" --direct "$L/libvulkan_lvp.so"
direct=$?
echo "--- without it"
"$PROBE"
without=$?
[ "$with" -eq 0 ] && [ "$direct" -eq 0 ] && [ "$without" -ne 0 ]
