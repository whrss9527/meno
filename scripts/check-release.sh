#!/usr/bin/env bash
# Check release metadata before building or publishing a version.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
version="$(cat VERSION)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::VERSION must contain a release version, got: $version" >&2
  exit 1
fi
if [[ $# -gt 0 && "${1#v}" != "$version" ]]; then
  echo "::error::Requested version $1 does not match VERSION ($version)" >&2
  exit 1
fi
notes=".github/releases/v${version}.md"
if [[ ! -s "$notes" ]]; then
  echo "::error::Release notes are missing or empty: $notes" >&2
  exit 1
fi
