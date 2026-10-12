#!/usr/bin/env bash
# Inspect/register the extension in an isolated macOS CI build.
set -euo pipefail
APP="${1:-build/Meno.app}"
WIDGET="$APP/Contents/PlugIns/MenoWidgets.appex"
[[ -d "$WIDGET" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WIDGET/Contents/Info.plist")" == io.github.whrss9527.meno.widgets ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$WIDGET/Contents/Info.plist")" == com.apple.widgetkit-extension ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$WIDGET/Contents/Info.plist")" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" ]]
codesign --verify --deep --strict "$APP"
trap 'pluginkit -r "$WIDGET" >/dev/null 2>&1 || true' EXIT
pluginkit -a "$WIDGET"
listing=$(pluginkit -m -A -D -v -i io.github.whrss9527.meno.widgets)
[[ "$listing" == *io.github.whrss9527.meno.widgets* ]]
echo 'Meno widget bundle and registration verified'
