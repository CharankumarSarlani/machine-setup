#!/bin/bash
# Runs every test, plus shellcheck. No network, no changes to your machine:
# each test builds a fake HOME and stubs brew, npm, gh and code.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FAILED=0

printf '%-22s ' "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$REPO/install.sh" "$HERE"/*.sh; then echo "clean"; else FAILED=1; fi
else
  echo "skipped (brew install shellcheck)"
fi

for test in "$HERE"/test-*.sh; do
  printf '%-22s ' "$(basename "$test")"
  if ! bash "$test" > "${TMPDIR:-/tmp}/mstest.$$" 2>&1; then FAILED=1; fi
  tail -1 "${TMPDIR:-/tmp}/mstest.$$"
done

printf '%-22s ' "test-gacp.zsh"
if ! zsh "$HERE/test-gacp.zsh" > "${TMPDIR:-/tmp}/mstest.$$" 2>&1; then FAILED=1; fi
tail -1 "${TMPDIR:-/tmp}/mstest.$$"
rm -f "${TMPDIR:-/tmp}/mstest.$$"

echo
if [ "$FAILED" -eq 0 ]; then echo "All tests passed."; else echo "Some tests FAILED."; fi
exit "$FAILED"
