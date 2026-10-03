#!/usr/bin/env bash
#
# Checks on this Mac that Meno moves an item the pointer cannot reach, as CI
# does on each macOS version it builds on. A new menu bar item, wider than
# the screen, appears in the Stash; even with every item shown its middle is
# off the screen, like an item behind the camera housing of a MacBook.
# Applying a scene that keeps it visible has to move it there by its window.
#
# Usage: scripts/check-moving.sh [path/to/Meno.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/Meno.app}"
BINARY="$APP/Contents/MacOS/Meno"
SUPPORT="$HOME/Library/Application Support/Meno"
WORK="$(mktemp -d)"
LOG="$WORK/meno.log"
HELPER_LOG="$WORK/helper.log"
# The key Meno gives the helper's item: its process name, and the only item.
KEY="MenoE2EWide#solo"

if [[ ! -x "$BINARY" ]]; then
  echo "No app at $APP; build it with make app" >&2
  exit 1
fi
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 27 ]]; then
  echo "On macOS 27 menu bar items have no windows of their own; nothing to check."
  exit 0
fi
if pgrep -x Meno >/dev/null; then
  echo "Meno is running; quit it first, as the copy checked would replace it" >&2
  exit 1
fi
if [[ -e "$SUPPORT/settings.json" ]]; then
  echo "Meno has settings on this Mac; this check needs a Mac without them" >&2
  exit 1
fi

meno=""
helper=""
cleanup() {
  for pid in "$helper" "$meno"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -f "$SUPPORT/settings.json"
}
trap cleanup EXIT

fail() {
  echo "::error::$*"
  echo "::group::Meno's output"
  cat "$LOG" 2>/dev/null || true
  echo "::endgroup::"
  echo "::group::The helper's output"
  cat "$HELPER_LOG" 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

# Runs a check once a second until it passes, for at most $1 seconds.
wait_for() {
  local seconds="$1"
  shift
  for _ in $(seq 1 "$seconds"); do
    if "$@"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

log_has() {
  grep -q -- "$1" "$LOG" 2>/dev/null
}

# Whether a file has more than $3 lines that match $1: counted anew on
# each try, as wait_for runs it again.
has_more_lines() {
  [[ "$(grep -c -- "$1" "$2" 2>/dev/null || true)" -gt "$3" ]]
}

# Whether the helper's item is on the screen (1) or not (0), as the helper
# reports when asked.
helper_on_screen() {
  local before
  before="$(grep -c '^E2E_ITEM ' "$HELPER_LOG" || true)"
  kill -USR1 "$helper"
  wait_for 5 has_more_lines '^E2E_ITEM ' "$HELPER_LOG" "$before" || return 1
  grep '^E2E_ITEM ' "$HELPER_LOG" | tail -1 | grep -q "on_screen=$1"
}

# Asks Meno for its report and prints it once it is there.
meno_report() {
  local before
  before="$(grep -c '^MENO_DIAG report' "$LOG" || true)"
  kill -USR1 "$meno"
  wait_for 20 has_more_lines '^MENO_DIAG report' "$LOG" "$before" || return 1
  # The last report runs up to the next line of Meno's own.
  awk '/^MENO_DIAG report/ { report = ""; inside = 1; next } /^MENO_DIAG / { inside = 0 } inside { report = report $0 "\n" } END { printf "%s", report }' "$LOG"
}

# Whether Meno lists the helper's item in section $1.
item_in() {
  meno_report | grep -E "^  $1 +x=.* $KEY " >/dev/null
}

# Showing items in the menu bar rather than in the Shelf, new items left
# where macOS puts them, and a scene that keeps the helper's item visible.
mkdir -p "$SUPPORT"
cat > "$SUPPORT/settings.json" <<EOF
{
  "general" : { "revealStyle" : "menuBar", "newItemPolicy" : "ignore" },
  "onboardingCompleted" : true,
  "scenes" : [
    {
      "id" : "0E2E0E2E-0000-4000-8000-000000000001",
      "name" : "Wide",
      "symbol" : "square.grid.2x2",
      "layout" : { "visible" : [ "$KEY" ], "hidden" : [ ], "stash" : [ ] },
      "createdAt" : 0,
      "updatedAt" : 0
    }
  ]
}
EOF

echo "==> Building the helper item"
swiftc -O -o "$WORK/MenoE2EWide" "$ROOT/scripts/e2e/StatusItemHelper.swift"

echo "==> Starting Meno"
# Launched directly rather than with open, so that the environment reaches it.
MENO_DIAG=1 "$BINARY" > "$LOG" 2>&1 &
meno=$!
wait_for 60 log_has '^MENO_DIAG ready' || fail "Meno did not get ready"
if log_has 'Accessibility: missing'; then
  fail "Meno has no Accessibility permission on this Mac"
fi

echo "==> Adding a menu bar item wider than the screen"
"$WORK/MenoE2EWide" --wide > "$HELPER_LOG" 2>&1 &
helper=$!
wait_for 15 grep -q '^E2E_ITEM ' "$HELPER_LOG" || fail "The helper item did not start"
wait_for 15 helper_on_screen 0 || fail "The new item is not hidden"
wait_for 20 item_in stash || fail "Meno does not list the new item in the Stash"

echo "==> Applying a scene that keeps it visible"
open "meno://scene/Wide"
wait_for 30 item_in visible || fail "Applying the scene did not move the item into Visible"
log_has "^MENO_DIAG move $KEY by window" || fail "Meno moved the item without going through its window"

echo "==> Hiding the other items"
open "meno://hide"
wait_for 15 helper_on_screen 1 || fail "The item did not stay in the menu bar as a visible item"

echo "Moving an item out of reach of the pointer works on macOS $(sw_vers -productVersion)."
echo "::group::Meno's report"
meno_report || true
echo "::endgroup::"
echo "::group::Moves"
grep '^MENO_DIAG move' "$LOG" || true
echo "::endgroup::"
