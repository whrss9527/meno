#!/bin/bash
# Prints the release notes for a tag: .github/releases/<tag>.md, written by hand for each version.
#   scripts/release-notes.sh v0.10.0 > notes.md
set -euo pipefail
cd "$(dirname "$0")/.."
tag="v${1#v}"
notes=".github/releases/${tag}.md"
if [[ -f "$notes" ]]; then
  cat "$notes"
else
  echo "::warning::${notes} is missing, so the release has no notes" >&2
fi
