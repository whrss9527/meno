#!/usr/bin/env bash
#
# Launches the built app, leaves it alone and reports what it costs while
# idle: the CPU it used over a minute, how often it woke up and its memory.
# It measures twice: with the default settings and nothing else in the menu
# bar, the least Meno costs, and as Meno is often used, with the items of 20
# other apps, hidden items shown on hover and a rule that waits for an app
# to come to the front. CI runs it for the main branch, adds the numbers to
# the run's summary and fails when Meno uses more CPU or memory than allowed.
#
# Usage: scripts/measure-footprint.sh [path/to/Meno.app]
#
# Environment:
#   SETTLE   seconds between Meno getting ready and measuring (default 30)
#   WINDOW   seconds measured (default 60)
#   ITEMS    other apps' menu bar items in the second measurement (default 20)
#   HOVER    1 to show hidden items on hover in the second measurement, 0 not
#            to (default 1)
#   MAX_CPU  percent of one core Meno may use in either (default 0.5)
#   MAX_RSS  MB of resident memory Meno may use in either (default 100)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/Meno.app}"
BINARY="$APP/Contents/MacOS/Meno"
SETTLE="${SETTLE:-30}"
WINDOW="${WINDOW:-60}"
ITEMS="${ITEMS:-20}"
HOVER="${HOVER:-1}"
MAX_CPU="${MAX_CPU:-0.5}"
MAX_RSS="${MAX_RSS:-100}"
SUPPORT="$HOME/Library/Application Support/Meno"
WORK="$(mktemp -d)"

if [[ ! -x "$BINARY" ]]; then
  echo "No app at $APP; build it with make app" >&2
  exit 1
fi
if pgrep -x Meno >/dev/null; then
  echo "Meno is running; quit it first, as the copy measured would replace it" >&2
  exit 1
fi

# Settings someone already has are used as they are, for the first
# measurement only: the second one would replace them.
own_settings=0
if [[ -e "$SUPPORT/settings.json" ]]; then
  own_settings=1
fi

meno=""
helpers=""
stop() {
  for pid in $helpers $meno; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  helpers=""
  meno=""
}
cleanup() {
  stop
  if [[ "$own_settings" == 0 ]]; then
    rm -f "$SUPPORT/settings.json"
  fi
}
trap cleanup EXIT

log=""
fail() {
  echo "::group::Meno's output"
  cat "$log" 2>/dev/null || true
  echo "::endgroup::"
  echo "::error::$*"
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

rows=""
failures=""
accessibility="granted"
# The items Meno saw in the first measurement, before others were added.
baseline=0

# Launches Meno, adds $2 other apps' items once it is ready, waits SETTLE
# seconds and measures it for WINDOW seconds. $1 names the measurement in
# the summary; the arguments after it are lines Meno's report has to
# contain, to show that it read its settings.
measure() {
  local name="$1" items="$2"
  shift 2
  log="$WORK/meno-$items.log"
  # Launched directly rather than with open, so that the environment reaches it.
  MENO_DIAG=1 "$BINARY" > "$log" 2>&1 &
  meno=$!
  wait_for 60 grep -q '^MENO_DIAG ready' "$log" || fail "Meno did not get ready"
  while [[ $# -gt 0 ]]; do
    grep -q -- "$1" "$log" || fail "Meno did not read its settings: its report has no “$1”"
    shift
  done
  local i
  for ((i = 1; i <= items; i++)); do
    "$WORK/items/MenoItem$(printf %02d "$i")" > /dev/null 2>&1 &
    helpers="$helpers $!"
  done
  sleep "$SETTLE"
  kill -0 "$meno" 2>/dev/null || fail "Meno quit during launch"

  local wake_start start cpu_start cpu_end end wake_end rss_kb
  wake_start="$(idle_wakeups "$meno")"
  start="$(now)"
  cpu_start="$(cpu_seconds "$meno")"
  ps -A -o pid=,time= > "$WORK/cpu-before"
  sleep "$WINDOW"
  ps -A -o pid=,time= > "$WORK/cpu-after"
  cpu_end="$(cpu_seconds "$meno")"
  end="$(now)"
  wake_end="$(idle_wakeups "$meno")"
  rss_kb="$(ps -o rss= -p "$meno" | tr -d ' ')"
  kill -0 "$meno" 2>/dev/null || fail "Meno quit while idle"

  local cpu_percent wakeups="n/a" rss_mb last_scan footprint_kb footprint="n/a" scans seen
  cpu_percent="$(awk -v a="$cpu_start" -v b="$cpu_end" -v s="$start" -v e="$end" 'BEGIN { printf "%.2f", (b - a) / (e - s) * 100 }')"
  if [[ -n "$wake_start" && -n "$wake_end" ]]; then
    wakeups="$(awk -v a="$wake_start" -v b="$wake_end" -v s="$start" -v e="$end" 'BEGIN { printf "%.1f", (b - a) / (e - s) }') per second"
  fi
  rss_mb="$(awk -v k="$rss_kb" 'BEGIN { printf "%.1f", k / 1024 }')"
  local system_cpu skipped_scans all_scans skip_ratio
  system_cpu="$(python3 "$ROOT/scripts/e2e/process-cpu.py" "$WORK/cpu-before" "$WORK/cpu-after" "$(awk -v s="$start" -v e="$end" 'BEGIN { print e-s }')")"
  last_scan="$(grep '^MENO_DIAG scan ' "$log" | grep -v 'mode=skipped' | tail -1 || true)"
  value() {
    printf '%s\n' "$last_scan" | tr ' ' '\n' | awk -F= -v key="$1" '$1 == key { print $2 }'
  }
  footprint_kb="$(value footprint_kb)"
  if [[ -n "$footprint_kb" && "$footprint_kb" != 0 ]]; then
    footprint="$(awk -v k="$footprint_kb" 'BEGIN { printf "%.1f MB", k / 1024 }')"
  fi
  scans="$(grep -c '^MENO_DIAG scan ' "$log" || true)"
  skipped_scans="$(grep -c '^MENO_DIAG scan mode=skipped ' "$log" || true)"
  all_scans="$scans"
  skip_ratio="$(awk -v n="$skipped_scans" -v total="$all_scans" 'BEGIN { printf "%.1f", total ? n/total*100 : 0 }')"
  seen="$(value items)"
  [[ -n "$last_scan" ]] || fail "Meno produced no scan to measure"
  if [[ "$last_scan" == *"accessibility=missing"* ]]; then
    fail "Accessibility is missing; the menu bar workload was not measured"
  elif [[ "${seen:-0}" -lt $((baseline + items)) ]]; then
    fail "Meno sees ${seen:-no} menu bar items, not the ${baseline} it saw before and the ${items} added"
  fi
  if [[ "$items" == 0 ]]; then
    baseline="${seen:-0}"
  fi

  rows="$rows| $name | ${cpu_percent} % | ${wakeups} | ${footprint} | ${rss_mb} MB | ${seen} | $(value ms) ms | ${scans} | ${skip_ratio} % | ${system_cpu} % |"$'\n'
  if awk -v c="$cpu_percent" -v m="$MAX_CPU" 'BEGIN { exit !(c > m) }'; then
    failures="$failures$name: Meno used ${cpu_percent} % of a core while idle, more than ${MAX_CPU} %"$'\n'
  fi
  if awk -v r="$rss_mb" -v m="$MAX_RSS" 'BEGIN { exit !(r > m) }'; then
    failures="$failures$name: Meno used ${rss_mb} MB of resident memory, more than ${MAX_RSS} MB"$'\n'
  fi
  echo "::group::Meno's output, $name"
  cat "$log"
  echo "::endgroup::"
  stop
}

# First as after setting Meno up, past the welcome window.
mkdir -p "$SUPPORT"
if [[ "$own_settings" == 1 ]]; then
  measure "Your settings" 0
else
  printf '{ "onboardingCompleted" : true }\n' > "$SUPPORT/settings.json"
  measure "Default settings" 0
fi

# Then as Meno is often used: other apps' items arrive while it runs and
# land in the Stash. Each one is a copy of the helper under a name of its
# own, as Meno tells apps without a bundle identifier apart by their names.
if [[ "$own_settings" == 0 ]]; then
  mkdir -p "$WORK/items"
  swiftc -O -o "$WORK/items/MenoItem01" "$ROOT/scripts/e2e/StatusItemHelper.swift"
  for ((i = 2; i <= ITEMS; i++)); do
    cp "$WORK/items/MenoItem01" "$WORK/items/MenoItem$(printf %02d "$i")"
  done
  hover=false
  hover_line="Reveal: .* · hover off · "
  name="${ITEMS} other items, a rule"
  if [[ "$HOVER" == 1 ]]; then
    hover=true
    hover_line="Reveal: .* · hover on · "
    name="${ITEMS} other items, hover, a rule"
  fi
  cat > "$SUPPORT/settings.json" <<EOF
{
  "onboardingCompleted" : true,
  "reveal" : { "onHover" : $hover },
  "rules" : [
    {
      "id" : "0E2E0E2E-0000-4000-8000-000000000003",
      "name" : "Safari in front",
      "conditions" : [ { "appFrontmost" : { "bundleID" : "com.apple.Safari" } } ],
      "action" : { "revealHidden" : { } }
    }
  ]
}
EOF
  measure "$name" "$ITEMS" '^Rules: 1, ' "$hover_line"
else
  echo "Measured once, with the settings Meno has on this Mac; the second measurement needs a Mac without them."
fi

summary="$(cat <<EOF
### Footprint on macOS $(sw_vers -productVersion) ($(uname -m))

Meno idle for ${WINDOW} seconds, ${SETTLE} seconds after it got ready. It may use up to ${MAX_CPU} % of one core and ${MAX_RSS} MB of resident memory. Accessibility: ${accessibility}. Periodic scan gate: ${MENO_SCAN_GATE:-1}. All-process CPU counts processes present at both snapshots, excluding exited processes; runner background activity can affect it.

| | CPU, of one core | Idle wake-ups | Memory (as Activity Monitor counts it) | Resident memory | Menu bar items | Last full scan took | Scan checks | Skipped checks | All-process CPU, of one core |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
${rows}
EOF
)"

echo "$summary"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '%s\n\n' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
if [[ -n "$failures" ]]; then
  printf '%s' "$failures" | while IFS= read -r line; do
    echo "::error::$line"
  done
  exit 1
fi
