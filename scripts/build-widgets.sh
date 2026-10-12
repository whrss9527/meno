#!/usr/bin/env bash
# Build the extension independently; the app/Core stay on SwiftPM.
set -euo pipefail
cd "$(dirname "$0")/.."
XCODEGEN_VERSION=2.44.1
CHECKSUM=a2e905fb68446e9bb4008cdfe2e13e3f176d0cbcca828b71770f8e53fca91b73
TOOLS="$PWD/.build/tools/xcodegen-$XCODEGEN_VERSION"
GENERATOR="$TOOLS/xcodegen/bin/xcodegen"
if [[ ! -x "$GENERATOR" ]]; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  curl --fail --location --retry 2 --output "$WORK/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
  printf '%s  %s\n' "$CHECKSUM" "$WORK/xcodegen.zip" | shasum -a 256 -c -
  mkdir -p "$TOOLS"
  ditto -x -k "$WORK/xcodegen.zip" "$TOOLS"
fi
[[ "$($GENERATOR --version)" == "Version: $XCODEGEN_VERSION" ]]
"$GENERATOR" generate --spec widget-project.yml --project .build/widget-project
ARCH_FLAGS=(ONLY_ACTIVE_ARCH=YES)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=("ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
fi
xcodebuild build -project .build/widget-project/MenoWidgets.xcodeproj -scheme MenoWidgets \
  -configuration Release -derivedDataPath .build/widgets CODE_SIGNING_ALLOWED=NO \
  "MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" "${ARCH_FLAGS[@]}"
mkdir -p "$APP/Contents/PlugIns"
ditto .build/widgets/Build/Products/Release/MenoWidgets.appex "$APP/Contents/PlugIns/MenoWidgets.appex"
SIGN_ARGS=(--force --options runtime --sign "$SIGN_IDENTITY" --entitlements Widgets/MenoWidgets.entitlements)
if [[ "$SIGN_IDENTITY" != "-" ]]; then SIGN_ARGS+=(--timestamp); else SIGN_ARGS+=(--timestamp=none); fi
if [[ -n "${SIGN_KEYCHAIN:-}" ]]; then SIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN"); fi
codesign "${SIGN_ARGS[@]}" "$APP/Contents/PlugIns/MenoWidgets.appex"
