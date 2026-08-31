#!/bin/bash

# shellcheck disable=SC2319,SC2088,SC2034
#   SC2319: "<command>; check <label> $?" is the assertion idiom here — $? is
#           meant to carry the condition's status.
#   SC2088: "~/.zshrc" strings are labels printed to the reader, not paths.
#   SC2034: globals below are read by the install.sh functions we source.
# Exercises the real configure_shell / build_shell_block bodies against a fake HOME.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAILN=0
check() { # check <label> <condition-result>
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok    $1"
  else FAILN=$((FAILN+1)); echo "  FAIL  $1"; fi
}

# The real script minus its final `main "$@"` line.
sed -E '$d' "$REPO/install.sh" > "$WORK/lib.sh"
grep -q 'main "\$@"' "$REPO/install.sh" || { echo "expected main call on last line"; exit 1; }

export HOME="$WORK/home"
mkdir -p "$HOME"
# shellcheck source=/dev/null
. "$WORK/lib.sh"

LOG_FILE="$WORK/log"; : > "$LOG_FILE"
TMP_DIR="$WORK/tmp"; mkdir -p "$TMP_DIR"
RUN_OUT="$TMP_DIR/out"
CONFIG_DIR="$REPO"
DRY_RUN=0

echo "== no ~/.zshrc -> created"
configure_shell >/dev/null
[ -f "$HOME/.zshrc" ]; check "~/.zshrc created" $?
grep -qxF '# >>> machine-setup >>>' "$HOME/.zshrc"; check "start marker present" $?
grep -qxF '# <<< machine-setup <<<' "$HOME/.zshrc"; check "end marker present" $?
grep -q 'gacp()' "$HOME/.zshrc"; check "functions.zsh inlined" $?
grep -q "alias gp='git push'" "$HOME/.zshrc"; check "aliases.zsh inlined" $?
grep -q 'brew shellenv' "$HOME/.zshrc"; check "path.zsh inlined" $?
[ "$(grep -c 'machine-setup >>>' "$HOME/.zshrc")" -eq 1 ]; check "exactly one block" $?

echo "== §14.3 re-run leaves ~/.zshrc unchanged"
cp "$HOME/.zshrc" "$WORK/before"
N_SKIP_BEFORE=$N_SKIP
configure_shell >/dev/null
cmp -s "$WORK/before" "$HOME/.zshrc"; check "byte-identical after re-run" $?
[ "$N_SKIP" -gt "$N_SKIP_BEFORE" ]; check "reported as skipped" $?
[ ! -d "$HOME/Library/Application Support/machine-setup/backups" ]; check "no backup made on no-op" $?

echo "== §14.4 hand-edits above and below the markers survive"
{ echo "# MY OWN LINE ABOVE"; cat "$HOME/.zshrc"; echo "export MY_OWN_VAR=1"; } > "$WORK/edited"
cp "$WORK/edited" "$HOME/.zshrc"
# Change the generated content so a rewrite is actually forced.
printf '\nexport MACHINE_SETUP_PROBE=1\n' >> "$REPO/shell/aliases.zsh"
configure_shell >/dev/null
sed -E -i '' '/MACHINE_SETUP_PROBE/d' "$REPO/shell/aliases.zsh"
sed -E -i '' '${/^$/d;}' "$REPO/shell/aliases.zsh"
head -1 "$HOME/.zshrc" | grep -qxF '# MY OWN LINE ABOVE'; check "line above markers survived" $?
tail -1 "$HOME/.zshrc" | grep -qxF 'export MY_OWN_VAR=1'; check "line below markers survived" $?
grep -q 'MACHINE_SETUP_PROBE' "$HOME/.zshrc"; check "block content was refreshed" $?
[ "$(grep -c 'machine-setup >>>' "$HOME/.zshrc")" -eq 1 ]; check "still exactly one block" $?
ls "$HOME/Library/Application Support/machine-setup/backups/" >/dev/null 2>&1; check "backup written before the edit" $?

echo "== markers absent, existing file with no trailing newline"
printf 'export FOO=1' > "$HOME/.zshrc"   # deliberately no final newline
configure_shell >/dev/null
head -1 "$HOME/.zshrc" | grep -qxF 'export FOO=1'; check "existing line not glued to marker" $?
grep -qxF '# >>> machine-setup >>>' "$HOME/.zshrc"; check "block appended" $?

echo "== Brewfile parsing"
COUNT="$(parse_brewfile "$REPO/Brewfile" | wc -l | tr -d ' ')"
[ "$COUNT" -eq 34 ]; check "34 entries parsed (got $COUNT)" $?
parse_brewfile "$REPO/Brewfile" | grep -qx 'brew postgresql@17'; check "versioned formula parsed" $?
parse_brewfile "$REPO/Brewfile" | grep -qx 'vscode qwtel.sqlite-viewer'; check "vscode entry parsed" $?
parse_brewfile "$REPO/Brewfile" | grep -qx 'cask intellij-idea-ce'; check "cask entry parsed" $?
! parse_brewfile "$REPO/Brewfile" | grep -q '^#'; check "comments ignored" $?

echo
echo "$PASS passed, $FAILN failed"
[ "$FAILN" -eq 0 ]
