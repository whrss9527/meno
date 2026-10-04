#!/usr/bin/env bash
# Run production checking, downloading, verification, swapping, relaunching,
# cleanup and rollback in disposable ad hoc bundles with a test entry point.
# Does not start menu-bar controllers or modify Meno's settings/preferences.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/meno-update-e2e.XXXXXX")"
WORK="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$WORK")"
IDENTIFIER="io.github.whrss9527.meno.update-test.$(uuidgen | tr '[:upper:]' '[:lower:]')"
SERVER=""
cleanup() {
  if [[ -n "$SERVER" ]]; then kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true; fi
  python3 - "$WORK" <<'PY'
import os, signal, subprocess, sys
root = sys.argv[1]
for row in subprocess.check_output(['ps', '-A', '-o', 'pid=,command='], text=True).splitlines():
    pid, _, command = row.strip().partition(' ')
    if command.startswith(root + '/') or (command.startswith('/bin/sh -c ') and root in command):
        try: os.kill(int(pid), signal.SIGTERM)
        except ProcessLookupError: pass
PY
  local leftovers
  leftovers="$(defaults read "$IDENTIFIER" UpdateLeftovers 2>/dev/null || true)"
  if [[ -n "$leftovers" && -f "$leftovers/Meno.zip" ]]; then rm -rf "$leftovers"; fi
  defaults delete "$IDENTIFIER" 2>/dev/null || true
  if [[ "${MENO_UPDATE_TEST_KEEP:-0}" != 1 ]]; then rm -rf "$WORK"; else echo "Test files: $WORK"; fi
}
trap cleanup EXIT
fail() {
  echo "::error::$*"
  cat "$WORK"/*/failed "$WORK"/*/driver.log "$WORK"/*/server.log "$WORK"/*/bundle-path "$WORK"/*/cleanup-state 2>/dev/null || true
  exit 1
}
wait_file() {
  local seconds="$1" file="$2" scene="$3"
  for ((i=0; i<seconds*5; i++)); do
    [[ ! -f "$scene/failed" ]] || fail "$(cat "$scene/failed")"
    [[ ! -f "$file" ]] || return 0
    sleep 0.2
  done
  fail "Timed out waiting for $file"
}
cd "$ROOT"
swift build
BIN="$(swift build --show-bin-path)"
# Compile a disposable entry point with the same production source, not mocks.
python3 - "$ROOT" "$WORK/sources" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
files = sorted(p for p in (root / 'Sources/Meno').rglob('*.swift') if p.name != 'MenoMain.swift')
files.append(root / 'scripts/helpers/UpdateDriver.swift')
pathlib.Path(sys.argv[2]).write_text('\n'.join('"' + str(p) + '"' for p in files))
PY
swiftc -parse-as-library -module-name Meno -I "$BIN/Modules" \
  @"$WORK/sources" "$BIN"/MenoCore.build/*.o \
  -framework AppKit -framework ApplicationServices -framework Carbon \
  -framework CoreAudio -framework CoreMediaIO -framework IOKit \
  -framework ServiceManagement -o "$WORK/UpdateDriver"
for scene in success rollback; do
  IDENTIFIER="io.github.whrss9527.meno.update-test.$(uuidgen | tr '[:upper:]' '[:lower:]')"
  SCENE="$WORK/$scene"
  mkdir -p "$SCENE/installed/Meno.app/Contents/MacOS" "$SCENE/release/Meno.app/Contents/MacOS"
  cp "$WORK/UpdateDriver" "$SCENE/installed/Meno.app/Contents/MacOS/Meno"
  cp "$WORK/UpdateDriver" "$SCENE/release/Meno.app/Contents/MacOS/Meno"
  # The endpoint is stable for both app versions after Launch Services relaunch.
  # Start the server after packing, then replace the endpoint in both bundles
  # and rebuild the archive before any requests are made.
  python3 - "$SCENE" "$IDENTIFIER" "$scene" <<'PY'
import pathlib, plistlib, sys
root, identifier, scene = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
for folder, version in [('installed', '0.0.1'), ('release', '0.0.2')]:
    info = dict(CFBundleIdentifier=identifier, CFBundleName='Meno Update Test', CFBundleExecutable='Meno',
                CFBundlePackageType='APPL', CFBundleShortVersionString=version, CFBundleVersion=version,
                LSUIElement=True, LSMinimumSystemVersion='14.0', MenoUpdateTestDirectory=str(root),
                MenoUpdateTestBroken=scene == 'rollback' and version == '0.0.2')
    (root / folder / 'Meno.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
  # Reserve a loopback port with the serving process; metadata is regenerated
  # below before the test driver starts.
  ditto -c -k --keepParent "$SCENE/release/Meno.app" "$SCENE/Meno.zip"
  python3 -u "$ROOT/scripts/helpers/update-server.py" "$SCENE" > "$SCENE/server.log" 2>&1 & SERVER=$!
  wait_file 10 "$SCENE/endpoint" "$SCENE"
  ENDPOINT="$(cat "$SCENE/endpoint")"
  for folder in installed release; do
    /usr/libexec/PlistBuddy -c "Add :MenoUpdateTestEndpoint string $ENDPOINT" "$SCENE/$folder/Meno.app/Contents/Info.plist"
    codesign --force --sign - --identifier "$IDENTIFIER" "$SCENE/$folder/Meno.app"
    codesign --verify --strict "$SCENE/$folder/Meno.app"
  done
  rm "$SCENE/Meno.zip"
  ditto -c -k --keepParent "$SCENE/release/Meno.app" "$SCENE/Meno.zip"
  python3 - "$SCENE" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1]); archive = root / 'Meno.zip'
p = root / 'latest.json'; data = json.loads(p.read_text())
data['assets'][0].update(size=archive.stat().st_size, digest='sha256:' + hashlib.sha256(archive.read_bytes()).hexdigest())
p.write_text(json.dumps(data))
PY
  "$SCENE/installed/Meno.app/Contents/MacOS/Meno" > "$SCENE/driver.log" 2>&1 &
  wait_file 30 "$SCENE/installing" "$SCENE"
  wait_file 30 "$SCENE/launched-0.0.2" "$SCENE"
  LEFTOVERS="$(cat "$SCENE/leftovers-path")"
  [[ -f "$LEFTOVERS/Meno.zip" ]] || fail 'Download folder was not retained during startup'
  if [[ "$scene" == rollback ]]; then
    wait_file 44 "$SCENE/put-back" "$SCENE"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCENE/installed/Meno.app/Contents/Info.plist")" == 0.0.1 ]] || fail 'Old version was not restored'
    python3 - "$SCENE" <<'PYTIME'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
elapsed = (root / 'put-back').stat().st_mtime - (root / 'launched-0.0.2').stat().st_mtime
assert elapsed < 45, f'Rollback notice took {elapsed:.1f}s'
print(f'Rollback and visible notice in {elapsed:.1f}s')
PYTIME
    cat "$SCENE/put-back"
  else
    sleep 10
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCENE/installed/Meno.app/Contents/Info.plist")" == 0.0.2 ]] || fail 'New version was not installed'
  fi
  [[ ! -f "$SCENE/failed" ]] || fail "$(cat "$SCENE/failed")"
  [[ -z "$(defaults read "$IDENTIFIER" UpdateLeftovers 2>/dev/null || true)" ]] || fail 'Leftovers preference was not cleared'
  if [[ -e "$LEFTOVERS" ]]; then ls -la "$LEFTOVERS"; fail 'Download folder was not removed'; fi
  # Every download was fetched from loopback and checked by the real installer.
  rg -q 'GET /Meno.zip.*200' "$SCENE/server.log" || fail 'Archive was not downloaded'
  python3 - "$SCENE/installed/Meno.app/Contents/MacOS/Meno" <<'PY'
import os, signal, subprocess, sys
for row in subprocess.check_output(['ps', '-A', '-o', 'pid=,command='], text=True).splitlines():
    pid, _, command = row.strip().partition(' ')
    if command.startswith(sys.argv[1]):
        try: os.kill(int(pid), signal.SIGTERM)
        except ProcessLookupError: pass
PY
  kill "$SERVER"; wait "$SERVER" 2>/dev/null || true; SERVER=""
  defaults delete "$IDENTIFIER" 2>/dev/null || true
  echo "Updating $scene passed"
done
