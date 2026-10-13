#!/usr/bin/env bash
# Exercise the production artwork cache with a suspended, in-memory backend.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/meno-image-cache.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cd "$ROOT"
swift build --target MenoCore > "$WORK/build.log" 2>&1
BIN="$(swift build --show-bin-path)"
swiftc -parse-as-library -I "$BIN/Modules" \
  Sources/Meno/Support/{AppInfo,ScreenGeometry}.swift \
  Sources/Meno/MenuBar/{MenuBarItem,WindowCapture,ItemImageCache}.swift \
  scripts/helpers/ImageCacheDriver.swift "$BIN"/MenoCore.build/*.o "$BIN"/FritCore.build/*.o \
  -framework AppKit -o "$WORK/Driver"
"$WORK/Driver"
