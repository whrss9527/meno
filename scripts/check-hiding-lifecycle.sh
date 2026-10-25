#!/usr/bin/env bash
# Check real status items and restart persistence with an isolated bundle/domain.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/meno-hiding-lifecycle.XXXXXX")"
IDENTIFIER="io.github.whrss9527.meno.lifecycle.$(uuidgen | tr '[:upper:]' '[:lower:]')"
cleanup() {
  defaults delete "$IDENTIFIER" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
cd "$ROOT"
swift build
BIN="$(swift build --show-bin-path)"
APP="$WORK/Lifecycle.app"
mkdir -p "$APP/Contents/MacOS"
python3 - "$ROOT" "$WORK/sources" "$APP" "$IDENTIFIER" <<'PY'
import pathlib, plistlib, sys
root, sources, app, identifier = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), sys.argv[4]
files = sorted(p for p in (root / 'Sources/Meno').rglob('*.swift') if p.name != 'MenoMain.swift')
files.append(root / 'scripts/helpers/HidingLifecycleDriver.swift')
sources.write_text('\n'.join('"' + str(p) + '"' for p in files))
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=identifier,
    CFBundleExecutable='Driver', CFBundleName='Meno Lifecycle Test', CFBundlePackageType='APPL',
    CFBundleShortVersionString='0.0.1', CFBundleVersion='1', LSUIElement=True,
    LSMinimumSystemVersion='14.0')))
PY
swiftc -parse-as-library -module-name Meno -I "$BIN/Modules" \
  @"$WORK/sources" "$BIN"/MenoCore.build/*.o "$BIN"/FritCore.build/*.o \
  -framework AppKit -framework ApplicationServices -framework Carbon \
  -framework CoreAudio -framework CoreMediaIO -framework IOKit \
  -framework ServiceManagement -o "$APP/Contents/MacOS/Driver"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/Driver" "$WORK/storage" exercise
"$APP/Contents/MacOS/Driver" "$WORK/storage" restart
