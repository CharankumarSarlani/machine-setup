#!/bin/bash

# shellcheck disable=SC2319,SC2088,SC2034
#   SC2319: "<command>; check <label> $?" is the assertion idiom here — $? is
#           meant to carry the condition's status.
#   SC2088: "~/.zshrc" strings are labels printed to the reader, not paths.
#   SC2034: globals below are read by the install.sh functions we source.
# The git identity prompts must read from /dev/tty, not stdin (§12).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAILN=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok    $1"; else FAILN=$((FAILN+1)); echo "  FAIL  $1"; fi; }

sed -E '$d' "$REPO/install.sh" > "$WORK/lib.sh"

cat > "$WORK/drive.sh" <<EOF
set -uo pipefail
export HOME="$WORK/home"
export GIT_CONFIG_GLOBAL="\$HOME/.gitconfig"
mkdir -p "\$HOME"
. "$WORK/lib.sh"
LOG_FILE="$WORK/log"; : > "\$LOG_FILE"
TMP_DIR="$WORK/tmp"; mkdir -p "\$TMP_DIR"
RUN_OUT="\$TMP_DIR/out"
DRY_RUN=0
configure_git_identity
EOF

# A pty, so /dev/tty inside the script is real. Blank line and a bad address
# check that ask() re-prompts rather than accepting them.
feed() { # feed <line>... — paced so the pty stays open between answers
  local line
  sleep 1
  for line in "$@"; do printf '%s\n' "$line"; sleep 0.5; done
  sleep 1
}
feed '' 'Ada Lovelace' 'notanemail' 'ada@example.com' \
  | script -q /dev/null bash "$WORK/drive.sh" > "$WORK/out" 2>&1

export GIT_CONFIG_GLOBAL="$WORK/home/.gitconfig"
[ "$(git config --global --get user.name)" = "Ada Lovelace" ]
check "name read from the tty" $?
[ "$(git config --global --get user.email)" = "ada@example.com" ]
check "email read from the tty" $?
grep -q 'does not look like an email' "$WORK/out"
check "rejected the malformed address and re-asked" $?

echo "== stdin is not consumed as answers"
# Under curl | bash stdin is the script text. Feed junk on stdin while the tty
# supplies the real answers; the junk must be ignored.
rm -f "$WORK/home/.gitconfig"
cat > "$WORK/drive2.sh" <<EOF
exec 0< "$WORK/junk"
$(cat "$WORK/drive.sh")
EOF
printf 'JUNK-FROM-STDIN\nMORE-JUNK\n' > "$WORK/junk"
feed 'Grace Hopper' 'grace@example.com' \
  | script -q /dev/null bash "$WORK/drive2.sh" > "$WORK/out2" 2>&1
[ "$(git config --global --get user.name)" = "Grace Hopper" ]
check "answers came from the tty, not stdin" $?

echo "== already configured asks nothing"
printf '' | script -q /dev/null bash "$WORK/drive.sh" > "$WORK/out3" 2>&1
grep -q 'skip  user.name (already Grace Hopper)' "$WORK/out3"
check "skips an already-set name" $?
grep -q 'skip  user.email (already grace@example.com)' "$WORK/out3"
check "skips an already-set email" $?

echo; echo "$PASS passed, $FAILN failed"; [ "$FAILN" -eq 0 ]
