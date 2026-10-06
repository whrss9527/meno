#!/bin/bash
# Prints the release notes for a tag: .github/releases/<tag>.md, written by hand for each version.
#   scripts/release-notes.sh v0.10.0 > notes.md
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/check-release.sh "$1"
cat ".github/releases/v${1#v}.md"
