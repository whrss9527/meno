#!/usr/bin/env bash
#
# Checks hiding from start to end on this Mac, as CI does on each macOS
# version it builds on. With Meno running, a new menu bar item appears at
# the left end, in the Stash, off the screen; showing all items brings it
# on the screen and hiding them takes it off again. Meno also has to list
# it in the Stash.
#
# Usage: scripts/check-hiding.sh [path/to/Meno.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/Meno.app}"
BINARY="$APP/Contents/MacOS/Meno"
SUPPORT="$HOME/Library/Application Support/Meno"
WORK="$(mktemp -d)"
LOG="$WORK/meno.log"
HELPER_LOG="$WORK/helper.log"

if [[ ! -x "$BINARY" ]]; then
  echo "No app at $APP; build it with make app" >&2
  exit 1
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

# Whether the helper's item is on the screen (1) or not (0), as the helper
# reports when asked.
helper_on_screen() {
  local before
  before="$(grep -c '^E2E_ITEM ' "$HELPER_LOG" || true)"
  kill -USR1 "$helper"
  wait_for 5 test "$(grep -c '^E2E_ITEM ' "$HELPER_LOG" || true)" -gt "$before" || return 1
  grep '^E2E_ITEM ' "$HELPER_LOG" | tail -1 | grep -q "on_screen=$1"
}

# Past the welcome window, and showing items in the menu bar rather than in
# the Shelf, so that where the item is tells whether it shows.
mkdir -p "$SUPPORT"
printf '{ "general" : { "revealStyle" : "menuBar" }, "onboardingCompleted" : true }\n' > "$SUPPORT/settings.json"

echo "==> Building the helper item"
swiftc -O -o "$WORK/MenoE2E" "$ROOT/scripts/e2e/StatusItemHelper.swift"

echo "==> Starting Meno"
# Launched directly rather than with open, so that the environment reaches it.
MENO_DIAG=1 "$BINARY" > "$LOG" 2>&1 &
meno=$!
wait_for 60 log_has '^MENO_DIAG ready' || fail "Meno did not get ready"
if log_has 'Accessibility: missing'; then
  fail "Meno has no Accessibility permission on this Mac"
fi

echo "==> Adding a menu bar item"
"$WORK/MenoE2E" > "$HELPER_LOG" 2>&1 &
helper=$!
wait_for 15 grep -q '^E2E_ITEM ' "$HELPER_LOG" || fail "The helper item did not start"
wait_for 15 helper_on_screen 0 || fail "The new item is not hidden"

echo "==> Showing all items"
open "meno://show/all"
wait_for 15 helper_on_screen 1 || fail "Showing all items did not bring the new item on the screen"

echo "==> Hiding them again"
open "meno://hide"
wait_for 15 helper_on_screen 0 || fail "Hiding did not take the new item off the screen"

echo "==> Asking Meno what it sees"
kill -USR1 "$meno"
wait_for 20 log_has '^MENO_DIAG report' || fail "Meno did not report"
report="$(sed -n '/^MENO_DIAG report/,$p' "$LOG")"
printf '%s\n' "$report" | grep -E '^  stash +x=.*E2E' >/dev/null || fail "Meno does not list the new item in the Stash"

echo "Hiding works on macOS $(sw_vers -productVersion)."
echo "::group::Meno's report"
printf '%s\n' "$report"
echo "::endgroup::"
