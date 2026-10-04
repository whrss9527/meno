#!/bin/bash
# Checks the gate and measures both production drag paths on disposable
# helper items. Run on a test Mac with Accessibility, as CI does.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
first=""
second=""
cleanup() {
  local status=$?
  if [[ "$status" != 0 ]]; then
    cat "$WORK/first.log" "$WORK/second.log" 2>/dev/null || true
  fi
  for pid in "$first" "$second"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$WORK"
}
trap cleanup EXIT
swiftc "$ROOT/Sources/Meno/Support/SecureInput.swift" "$ROOT/scripts/e2e/SecureInputCheck.swift" -o "$WORK/check"
"$WORK/check"
swiftc "$ROOT/Sources/Meno/MenuBar/EventSynthesizer.swift" "$ROOT/scripts/e2e/SecureInputProbe.swift" -o "$WORK/probe"
swiftc "$ROOT/scripts/e2e/SecureInputHolder.swift" -o "$WORK/holder"
swiftc "$ROOT/scripts/e2e/StatusItemHelper.swift" -o "$WORK/MenoSecureA"
cp "$WORK/MenoSecureA" "$WORK/MenoSecureB"
"$WORK/MenoSecureA" > "$WORK/first.log" 2>&1 &
first=$!
"$WORK/MenoSecureB" > "$WORK/second.log" 2>&1 &
second=$!
for _ in {1..15}; do
  if grep -q '^E2E_ITEM ' "$WORK/first.log" && grep -q '^E2E_ITEM ' "$WORK/second.log"; then break; fi
  sleep 1
done
grep -q '^E2E_ITEM ' "$WORK/first.log"
grep -q '^E2E_ITEM ' "$WORK/second.log"
sleep 2
"$WORK/probe" "$first" "$second" "$WORK/holder"
