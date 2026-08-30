#!/bin/bash

# shellcheck disable=SC2319,SC2088,SC2034
#   SC2319: "<command>; check <label> $?" is the assertion idiom here — $? is
#           meant to carry the condition's status.
#   SC2088: "~/.zshrc" strings are labels printed to the reader, not paths.
#   SC2034: globals below are read by the install.sh functions we source.
# §14.9 — a truncated download must do nothing at all.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

PASS=0; FAILN=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok    $1"; else FAILN=$((FAILN+1)); echo "  FAIL  $1"; fi; }

TOTAL=$(wc -c < "$REPO/install.sh" | tr -d ' ')
export HOME="$WORK/home"; mkdir -p "$HOME"

for pct in 10 25 50 75 90 99; do
  BYTES=$((TOTAL * pct / 100))
  OUT="$(head -c "$BYTES" "$REPO/install.sh" | bash 2>"$WORK/err")"
  STATUS=$?
  # Nothing may be printed to stdout and no log directory may appear:
  # every action lives inside main(), which a truncated file never reaches.
  [ -z "$OUT" ] && [ ! -d "$HOME/Library/Logs/machine-setup" ] && [ ! -f "$HOME/.zshrc" ]
  check "truncated at ${pct}% does nothing (exit $STATUS)" $?
done

# The whole file, by contrast, must reach main() and refuse politely.
OUT="$(bash "$REPO/install.sh" --help 2>&1)"
printf '%s' "$OUT" | grep -q 'Usage:'; check "complete file runs (--help works)" $?

echo; echo "$PASS passed, $FAILN failed"; [ "$FAILN" -eq 0 ]
