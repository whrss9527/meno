#!/usr/bin/env bash
#
# Launches the built app, leaves it alone and reports what it costs while
# idle: the CPU it used over a minute, how often it woke up and its memory.
# CI runs it after every build and adds the numbers to the run's summary.
#
# Usage: scripts/measure-footprint.sh [path/to/Meno.app]
#
# Environment:
#   SETTLE   seconds between launch and measuring (default 30)
#   WINDOW   seconds measured (default 60)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/Meno.app}"
BINARY="$APP/Contents/MacOS/Meno"
SETTLE="${SETTLE:-30}"
WINDOW="${WINDOW:-60}"
SUPPORT="$HOME/Library/Application Support/Meno"
WORK="$(mktemp -d)"
LOG="$WORK/meno.log"

if [[ ! -x "$BINARY" ]]; then
  echo "No app at $APP; build it with make app" >&2
  exit 1
fi
if pgrep -x Meno >/dev/null; then
  echo "Meno is running; quit it first, as the copy measured would replace it" >&2
  exit 1
fi

# Past the welcome window, as after setting Meno up. Settings someone
# already has are used as they are.
seeded=0
if [[ ! -e "$SUPPORT/settings.json" ]]; then
  mkdir -p "$SUPPORT"
  printf '{ "onboardingCompleted" : true }\n' > "$SUPPORT/settings.json"
  seeded=1
fi

pid=""
cleanup() {
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  if [[ "$seeded" == 1 ]]; then
    rm -f "$SUPPORT/settings.json"
  fi
}
trap cleanup EXIT

now() {
  perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

# The CPU time the process used so far, in seconds. ps prints it as
# [[hours:]minutes:]seconds.
cpu_seconds() {
  ps -o time= -p "$1" | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; printf "%.3f\n", s }'
}

# How often the process woke up from idle so far, or nothing where top
# does not tell.
idle_wakeups() {
  top -l 1 -c e -pid "$1" -stats pid,idlew 2>/dev/null \
    | awk -v pid="$1" '$1 == pid { gsub(/[^0-9]/, "", $2); print $2 }' || true
}

# Launched directly rather than with open, so that the environment reaches it.
MENO_DIAG=1 "$BINARY" > "$LOG" 2>&1 &
pid=$!
sleep "$SETTLE"
if ! kill -0 "$pid" 2>/dev/null; then
  cat "$LOG"
  echo "::error::Meno quit during launch"
  exit 1
fi

wake_start="$(idle_wakeups "$pid")"
start="$(now)"
cpu_start="$(cpu_seconds "$pid")"
sleep "$WINDOW"
cpu_end="$(cpu_seconds "$pid")"
end="$(now)"
wake_end="$(idle_wakeups "$pid")"
rss_kb="$(ps -o rss= -p "$pid" | tr -d ' ')"

if ! kill -0 "$pid" 2>/dev/null; then
  cat "$LOG"
  echo "::error::Meno quit while idle"
  exit 1
fi

cpu_percent="$(awk -v a="$cpu_start" -v b="$cpu_end" -v s="$start" -v e="$end" 'BEGIN { printf "%.2f", (b - a) / (e - s) * 100 }')"
wakeups="n/a"
if [[ -n "$wake_start" && -n "$wake_end" ]]; then
  wakeups="$(awk -v a="$wake_start" -v b="$wake_end" -v s="$start" -v e="$end" 'BEGIN { printf "%.1f", (b - a) / (e - s) }') per second"
fi
last_scan="$(grep '^MENO_DIAG scan ' "$LOG" | tail -1 || true)"
value() {
  printf '%s\n' "$last_scan" | tr ' ' '\n' | awk -F= -v key="$1" '$1 == key { print $2 }'
}
footprint_kb="$(value footprint_kb)"
footprint="n/a"
if [[ -n "$footprint_kb" && "$footprint_kb" != 0 ]]; then
  footprint="$(awk -v k="$footprint_kb" 'BEGIN { printf "%.1f MB", k / 1024 }')"
fi
scans="$(grep -c '^MENO_DIAG scan ' "$LOG" || true)"
accessibility="granted"
if [[ "$last_scan" == *"accessibility=missing"* ]]; then
  accessibility="missing, so Meno waits for it with Settings open"
fi

summary="$(cat <<EOF
### Footprint on macOS $(sw_vers -productVersion) ($(uname -m))

Meno idle for ${WINDOW} seconds, ${SETTLE} seconds after launch.

| | |
| --- | --- |
| CPU | ${cpu_percent} % of one core |
| Idle wake-ups | ${wakeups} |
| Memory (as Activity Monitor counts it) | ${footprint} |
| Resident memory | $(awk -v k="$rss_kb" 'BEGIN { printf "%.1f MB", k / 1024 }') |
| Menu bar items | $(value items) |
| Last scan took | $(value ms) ms |
| Scans since launch | ${scans} |
| Accessibility | ${accessibility} |
EOF
)"

echo "$summary"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '%s\n\n' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
echo "::group::Meno's output"
cat "$LOG"
echo "::endgroup::"
if awk -v c="$cpu_percent" 'BEGIN { exit !(c > 1) }'; then
  echo "::warning::Meno used ${cpu_percent} % of a core while idle"
fi
