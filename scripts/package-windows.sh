#!/bin/bash
# Repackages the upstream Windows binaries into the Linux package's layout: lavapipe from
# mesa-dist-win and the Vulkan loader from LunarG's runtime, both x64. Runs in Git Bash with
# the inputs already in sources/ (scripts/fetch.sh); writes
# dist/valle-lavapipe-$VERSION-windows-x86_64.tar.gz.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VERSION:?set VERSION, such as 0.1.0}"
NAME=valle-lavapipe-$VERSION-windows-x86_64
B=build/windows
rm -rf "$B" && mkdir -p "$B" dist
P="$B/$NAME"
mkdir -p "$P/lib" "$P/licenses"

echo "=== Extracting upstream binaries"
7z x -y -o"$B/mesa" sources/mesa3d-25.2.7-release-msvc.7z x64/vulkan_lvp.dll x64/lvp_icd.x86_64.json >/dev/null
7z x -y -o"$B/rt" sources/VulkanRT-X64-1.4.328.1-Components.zip >/dev/null
tar -xJf sources/mesa-25.2.7.tar.xz -C "$B" mesa-25.2.7/docs/license.rst mesa-25.2.7/licenses/MIT mesa-25.2.7/licenses/BSL-1.0

echo "=== Packaging"
# The manifest already names the driver beside it (".\\vulkan_lvp.dll").
cp "$B/mesa/x64/vulkan_lvp.dll" "$B/mesa/x64/lvp_icd.x86_64.json" "$P/lib/"
cp "$B/rt/VulkanRT-X64-1.4.328.1-Components/x64/vulkan-1.dll" "$P/lib/"
cp "$B/mesa-25.2.7/docs/license.rst" "$P/licenses/mesa.rst"
cp "$B/mesa-25.2.7/licenses/MIT" "$P/licenses/mesa-MIT.txt"
cp "$B/mesa-25.2.7/licenses/BSL-1.0" "$P/licenses/mesa-BSL-1.0.txt"
cp sources/mesa-dist-win-LICENSE "$P/licenses/mesa-dist-win.txt"
cp sources/llvm-LICENSE.TXT "$P/licenses/llvm.txt"
cp "$B/rt/VulkanRT-X64-1.4.328.1-Components/VulkanRT-License.txt" "$P/licenses/vulkan-runtime.txt"
cp THIRD_PARTY.md "$P/"

echo "=== Creating archive"
tar -C "$B" -czf "dist/$NAME.tar.gz" "$NAME"
echo "Built dist/$NAME.tar.gz"
