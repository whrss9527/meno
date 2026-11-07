#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:?Pass an absolute output directory outside the app installation folders}
[[ "$output" = /* && "$output" != /Applications* ]] || exit 2
swift build --jobs 2 --skip-update --scratch-path "$output/build" -Xswiftc -DMENO_UI_FIXTURE --product Meno
binary=$(swift build --skip-update --scratch-path "$output/build" --show-bin-path)
app="$output/MenoUIFixture.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary/Meno" "$app/Contents/MacOS/MenoUIFixture"
cp -R Resources/*.lproj "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.codex.fixture.meno</string>
<key>CFBundleExecutable</key><string>MenoUIFixture</string>
<key>CFBundleName</key><string>Meno UI Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>0.14.1-fixture</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf '%s\n' "$app"
