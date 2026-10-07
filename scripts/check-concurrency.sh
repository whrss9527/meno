#!/usr/bin/env bash
# Build in a fresh directory so incremental compilation cannot hide diagnostics.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d "${RUNNER_TEMP:-/tmp}/meno-concurrency.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
if ! swift build --scratch-path "$WORK/build" -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency > "$WORK/build.log" 2>&1; then
  cat "$WORK/build.log"
  exit 1
fi
python3 scripts/check-concurrency.py "$WORK/build.log" scripts/concurrency-baseline.json ${GITHUB_STEP_SUMMARY:+"$GITHUB_STEP_SUMMARY"}
