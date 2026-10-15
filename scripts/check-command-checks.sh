#!/usr/bin/env bash
# Compile the production command watcher without starting the app or its rules.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/meno-command-checks.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cd "$ROOT"
sources=(Sources/Meno/Automation/CommandChecks.swift scripts/helpers/CommandChecksDriver.swift)
if [ "$(uname -s)" = Darwin ]; then
  sources+=(Sources/Meno/Support/AppInfo.swift)
fi
swiftc -swift-version 5 -parse-as-library "${sources[@]}" -o "$WORK/Driver"
"$WORK/Driver"
