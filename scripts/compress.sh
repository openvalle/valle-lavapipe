#!/bin/sh
# Writes the driver of each package beside it, alone and Brotli-compressed, for an executable to
# embed: valle-lavapipe-{version}-linux-x86_64.so.br holds lib/libvulkan_lvp.so, and
# valle-lavapipe-{version}-windows-x86_64.dll.br lib/vulkan_lvp.dll. Each is checked to
# decompress to the packaged driver.
#   scripts/compress.sh dist/valle-lavapipe-0.1.0-linux-x86_64.tar.gz ...
set -eu
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
for archive in "$@"; do
  dir=$(dirname "$archive")
  case $archive in
  *-linux-*.tar.gz)
    name=$(basename "$archive" .tar.gz)
    tar -xzOf "$archive" "$name/lib/libvulkan_lvp.so" > "$T/driver"
    out="$dir/$name.so.br"
    ;;
  *-windows-*.zip)
    name=$(basename "$archive" .zip)
    unzip -p "$archive" "$name/lib/vulkan_lvp.dll" > "$T/driver"
    out="$dir/$name.dll.br"
    ;;
  *) echo "not a package: $archive"; exit 1 ;;
  esac
  [ -s "$T/driver" ] || { echo "no driver in $archive"; exit 1; }
  # Quality 9 is within 15% of 11's size, in a fraction of its time; the window is the most
  # a decoder must hold.
  brotli -q 9 -w 24 -f -o "$out" "$T/driver"
  brotli -dc "$out" | cmp - "$T/driver"
  echo "$out: $(wc -c < "$T/driver" | tr -d ' ') bytes -> $(wc -c < "$out" | tr -d ' ')"
done
