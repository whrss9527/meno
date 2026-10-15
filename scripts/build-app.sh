#!/usr/bin/env bash
#
# Builds Meno.app from the Swift package.
#
# Environment:
#   CONFIG         release (default) or debug
#   UNIVERSAL=1    build a universal (arm64 + x86_64) binary
#   SIGN_IDENTITY  codesign identity; defaults to "-" (ad-hoc)
#   SIGN_KEYCHAIN  keychain that holds the identity (optional)
#   VERSION        marketing version; defaults to the VERSION file
#   OUT_DIR        output directory; defaults to ./build
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Meno"
CONFIG="${CONFIG:-release}"
OUT_DIR="${OUT_DIR:-$ROOT/build}"
APP="$OUT_DIR/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${VERSION:-$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.1.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"

ARCHITECTURES=("$(uname -m)")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCHITECTURES=(arm64 x86_64)
fi

cd "$ROOT"

# The two SDK contracts come from the successful native/SwiftPM probe in #80.
# Emit constants during the actual app build; ordinary SwiftPM emits no intents.
INTENTS_WORK="$OUT_DIR/app-intents"
PROTOCOLS="$(python3 scripts/app-intents.py configure "$INTENTS_WORK")"
INTENTS_FLAGS=(-Xswiftc -emit-const-values -Xswiftc -Xfrontend
  -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$PROTOCOLS")

echo "==> Building $APP_NAME ($CONFIG)"
# A multi-arch SwiftPM invocation selects a different build backend. Build
# each slice explicitly so its actual constant values can be validated too.
BINARIES=()
for architecture in "${ARCHITECTURES[@]}"; do
  swift build -c "$CONFIG" --arch "$architecture" "${INTENTS_FLAGS[@]}" --product "$APP_NAME"
  BIN_DIR="$(swift build -c "$CONFIG" --arch "$architecture" "${INTENTS_FLAGS[@]}" --show-bin-path)"
  BINARIES+=("$BIN_DIR/$APP_NAME")
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
else
  cp "${BINARIES[0]}" "$APP/Contents/MacOS/$APP_NAME"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
for lproj in "$ROOT"/Resources/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"
metadata_args=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then metadata_args=(--universal); fi
python3 scripts/app-intents.py extract "$APP" "$INTENTS_WORK" --configuration "$CONFIG" ${metadata_args[@]+"${metadata_args[@]}"}

echo "==> Signing with identity: $SIGN_IDENTITY"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --options runtime --timestamp=none --sign - "$APP"
else
  keychain_args=()
  if [[ -n "${SIGN_KEYCHAIN:-}" ]]; then
    keychain_args=(--keychain "$SIGN_KEYCHAIN")
  fi
  codesign --force --options runtime --timestamp ${keychain_args[@]+"${keychain_args[@]}"} --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "==> Done: $APP"
