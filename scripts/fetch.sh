#!/bin/bash
# Downloads the named inputs from sources.txt into sources/ and checks their sha256. A file
# already there with the right hash is kept, so a rerun downloads nothing.
#   scripts/fetch.sh mesa-26.2.6.tar.xz llvm-project-23.1.5.src.tar.xz ...
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sources

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

for name in "$@"; do
  line=$(grep -E "^[0-9a-f]{64}  $name  " sources.txt) || { echo "$name: not in sources.txt"; exit 1; }
  read -r sum _ url <<<"$line"
  file="sources/$name"
  if [ -f "$file" ] && [ "$(sha256 "$file")" = "$sum" ]; then
    echo "ok (cached) $name"
    continue
  fi
  curl -fsSL --retry 5 --retry-all-errors --connect-timeout 30 -o "$file.part" "$url"
  got=$(sha256 "$file.part")
  if [ "$got" != "$sum" ]; then
    rm -f "$file.part"
    echo "$name: sha256 $got, expected $sum"
    exit 1
  fi
  mv "$file.part" "$file"
  echo "ok $name"
done
