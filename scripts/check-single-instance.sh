#!/usr/bin/env bash
# Exercise production arbitration without menu-bar controllers or user settings.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/meno-instance-e2e.XXXXXX")"
PIDS=()
cleanup() {
  for pid in "${PIDS[@]:-}"; do [[ -n "$pid" ]] || continue; kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT
cd "$ROOT"
swift build > "$WORK/build.log" 2>&1
BIN="$(swift build --show-bin-path)"
swiftc -parse-as-library -I "$BIN/Modules" \
  Sources/Meno/Support/{AppInfo,Log,SingleInstance}.swift \
  scripts/helpers/SingleInstanceDriver.swift "$BIN"/MenoCore.build/*.o \
  -framework AppKit -o "$WORK/Driver"
for iteration in 1 2 3; do
  SCENE="$WORK/$iteration"
  mkdir -p "$SCENE"
  IDENTIFIER="io.github.whrss9527.meno.instance-test.$(uuidgen | tr '[:upper:]' '[:lower:]')"
  for copy in first second; do
    APP="$SCENE/$copy.app"
    mkdir -p "$APP/Contents/MacOS"
    cp "$WORK/Driver" "$APP/Contents/MacOS/Driver"
    python3 - "$APP" "$IDENTIFIER" <<'PY'
import pathlib, plistlib, sys
app, identifier = pathlib.Path(sys.argv[1]), sys.argv[2]
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=identifier,
    CFBundleExecutable='Driver', CFBundleName='Meno Instance Test', CFBundlePackageType='APPL',
    CFBundleShortVersionString='9.9.9', CFBundleVersion='1', LSUIElement=True)))
PY
    codesign --force --sign - "$APP" > /dev/null 2>&1
    MENO_INSTANCE_TEST_DIR="$SCENE" "$APP/Contents/MacOS/Driver" > "$SCENE/$copy.log" 2>&1 &
    PIDS+=("$!")
  done
  ready=0
  for ((i=0; i<100; i++)); do
    ready=$(find "$SCENE" -name 'ready-*' | wc -l | tr -d ' ')
    [[ "$ready" = 2 ]] && break
    sleep 0.1
  done
  [[ "$ready" = 2 ]] || { cat "$SCENE"/*.log; echo '::error::Both copies did not become ready'; exit 1; }
  touch "$SCENE/go"
  sleep 3
  live=0
  for pid in "${PIDS[@]}"; do if kill -0 "$pid" 2>/dev/null; then live=$((live+1)); fi; done
  [[ "$live" = 1 ]] || { cat "$SCENE"/*.log; echo "::error::Expected one survivor after 3 seconds, got $live"; exit 1; }
  kill -0 "${PIDS[0]}" 2>/dev/null || { echo "::error::The lower PID must win"; exit 1; }
  echo "Simultaneous launch $iteration: exactly one survivor after 3 seconds"
  for pid in "${PIDS[@]:-}"; do [[ -n "$pid" ]] || continue; kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
  PIDS=()
done
