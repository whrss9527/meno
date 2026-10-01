#!/usr/bin/env bash
#
# Checks hiding from start to end on this Mac, as CI does on each macOS
# version it builds on. With Meno running, a new menu bar item appears at
# the left end, in the Stash, off the screen; showing all items brings it
# on the screen and hiding them takes it off again. Meno also has to list
# it in the Stash. Last, Meno starts with its Hidden divider right of the
# Meno icon and has to put it back on the icon's left.
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

echo "==> Showing the Hidden section"
open "meno://show"
shown=0
for _ in $(seq 1 10); do
  if meno_report | grep -q 'hidden shown · stash collapsed'; then
    shown=1
    break
  fi
  sleep 1
done
[[ "$shown" == 1 ]] || fail "meno://show did not show the Hidden section"
wait_for 3 helper_on_screen 0 || fail "Showing the Hidden section showed the Stash too"

echo "==> Showing all items"
open "meno://show/all"
wait_for 15 helper_on_screen 1 || fail "Showing all items did not bring the new item on the screen"

echo "==> Hiding them again"
open "meno://hide"
wait_for 15 helper_on_screen 0 || fail "Hiding did not take the new item off the screen"

echo "==> Asking Meno what it sees"
report="$(meno_report)" || fail "Meno did not report"
printf '%s\n' "$report" | grep -E '^  stash +x=.*E2E' >/dev/null || fail "Meno does not list the new item in the Stash"

echo "::group::Meno's report"
printf '%s\n' "$report"
echo "::endgroup::"

# Whether a report has the Hidden divider left of the Meno icon. Its line
# reads "Meno icon x=… w=… · hidden divider x=… w=… · …".
divider_in_order() {
  printf '%s\n' "$1" | awk '/^Meno icon x=/ {
    n = 0
    for (i = 1; i <= NF; i++) if ($i ~ /^[xw]=/) { split($i, kv, "="); value[++n] = kv[2] }
    found = 1
    ok = (n >= 4 && value[3] + value[4] <= value[1] + 1)
  } END { exit !(found && ok) }'
}

echo "==> Starting with the Hidden divider right of the Meno icon"
kill "$meno" 2>/dev/null || true
wait "$meno" 2>/dev/null || true
# Positions count from the right end of the menu bar.
defaults write io.github.whrss9527.meno "NSStatusItem Preferred Position meno.toggle" -float 400
defaults write io.github.whrss9527.meno "NSStatusItem Preferred Position meno.divider.hidden" -float 300
defaults write io.github.whrss9527.meno "NSStatusItem Preferred Position meno.divider.stash" -float 500
: > "$LOG"
MENO_DIAG=1 "$BINARY" > "$LOG" 2>&1 &
meno=$!
wait_for 60 log_has '^MENO_DIAG ready' || fail "Meno did not get ready again"
in_order=0
for _ in $(seq 1 20); do
  if report="$(meno_report)" && divider_in_order "$report"; then
    in_order=1
    break
  fi
  sleep 1
done
[[ "$in_order" == 1 ]] || fail "The Hidden divider did not end up left of the Meno icon"
if log_has '^MENO_DIAG repair meno.divider.hidden'; then
  echo "Meno put the Hidden divider back left of the Meno icon."
else
  echo "macOS kept the Hidden divider left of the Meno icon, so there was nothing to put back."
fi

echo "Hiding works on macOS $(sw_vers -productVersion)."
