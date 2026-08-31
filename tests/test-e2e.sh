#!/bin/bash

# shellcheck disable=SC2319,SC2088,SC2034
#   SC2319: "<command>; check <label> $?" is the assertion idiom here — $? is
#           meant to carry the condition's status.
#   SC2088: "~/.zshrc" strings are labels printed to the reader, not paths.
#   SC2034: globals below are read by the install.sh functions we source.
# End-to-end run of install.sh against stubbed brew/npm/code/gh, in a fake HOME.
# The only edit to the script is repointing the two hard-coded Homebrew prefixes
# at the fake one; every code path below that is the real thing.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

PASS=0; FAILN=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok    $1"; else FAILN=$((FAILN+1)); echo "  FAIL  $1"; fi; }

FAKE="$WORK/prefix"; mkdir -p "$FAKE/bin"
export HOME="$WORK/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
STATE="$WORK/state"; mkdir -p "$STATE"

cat > "$FAKE/bin/brew" <<STUB
#!/bin/bash
# Real commands may read stdin. If install.sh hands a loop's own stdin to the
# command it invokes, that command drains the list and the loop ends early —
# the bug that stopped a real run three packages in. Draining stdin here keeps
# the suite honest about it.
cat > /dev/null 2>&1
case "\$1 \$2" in
  "shellenv "*) echo 'export HOMEBREW_PREFIX="$FAKE"'; echo 'export PATH="$FAKE/bin:\$PATH"'; exit 0 ;;
esac
if [ "\$1" = "list" ]; then
  # Pretend jq and ghostty are already there.
  [ "\$2" = "--formula" ] && echo "jq"
  [ "\$2" = "--cask" ] && echo "ghostty"
  exit 0
fi
if [ "\$1" = "install" ]; then
  name="\${!#}"
  if [ "\$name" = "raylib" ]; then
    echo "Error: raylib: no bottle available for macOS 26" >&2
    exit 1
  fi
  echo "\$name" >> "$STATE/brew-installed"
  echo "Pouring \$name"
  exit 0
fi
exit 0
STUB

cat > "$FAKE/bin/npm" <<STUB
#!/bin/bash
# Real commands may read stdin. If install.sh hands a loop's own stdin to the
# command it invokes, that command drains the list and the loop ends early —
# the bug that stopped a real run three packages in. Draining stdin here keeps
# the suite honest about it.
cat > /dev/null 2>&1
[ "\$1" = "ls" ] && exit 0
if [ "\$1" = "install" ]; then echo "\${!#}" >> "$STATE/npm-installed"; exit 0; fi
exit 0
STUB

cat > "$FAKE/bin/code" <<STUB
#!/bin/bash
# Real commands may read stdin. If install.sh hands a loop's own stdin to the
# command it invokes, that command drains the list and the loop ends early —
# the bug that stopped a real run three packages in. Draining stdin here keeps
# the suite honest about it.
cat > /dev/null 2>&1
[ "\$1" = "--list-extensions" ] && { echo "esbenp.prettier-vscode"; exit 0; }
[ "\$1" = "--install-extension" ] && { echo "\$2" >> "$STATE/ext-installed"; exit 0; }
exit 0
STUB

cat > "$FAKE/bin/gh" <<STUB
#!/bin/bash
# Real commands may read stdin. If install.sh hands a loop's own stdin to the
# command it invokes, that command drains the list and the loop ends early —
# the bug that stopped a real run three packages in. Draining stdin here keeps
# the suite honest about it.
cat > /dev/null 2>&1
[ "\$1 \$2" = "auth status" ] && exit 0
if [ "\$1 \$2" = "auth setup-git" ]; then
  touch "$STATE/gh-setup-git"
  # What the real gh auth setup-git writes.
  git config --global --replace-all credential."https://github.com".helper "!gh auth git-credential"
  exit 0
fi
exit 0
STUB
chmod +x "$FAKE"/bin/*

sed -E "s#/opt/homebrew/bin/brew#$FAKE/bin/brew#g; s#/usr/local/bin/brew#$FAKE/bin/brew#g" \
  "$REPO/install.sh" > "$WORK/install.sh"
chmod +x "$WORK/install.sh"
# The config files must sit beside it for the local-checkout path to engage.
cp "$REPO/Brewfile" "$REPO/npm-packages.txt" "$WORK/"
cp -R "$REPO/git" "$REPO/shell" "$WORK/"

# Identity pre-set so this run needs no tty; the prompt path is tested separately.
git config --global user.name "Test User"
git config --global user.email "test@example.com"

cd "$REPO" || exit 1
OUT="$WORK/run1.txt"
# Answers for the git identity prompts, fed via the tty the script insists on.
"$WORK/install.sh" > "$OUT" 2>&1 < /dev/null
STATUS=$?

echo "== first run"
[ "$STATUS" -eq 2 ]; check "exit code 2 when something failed" $?
grep -q 'FAIL  raylib' "$OUT"; check "raylib reported as FAIL inline" $?
grep -q 'no bottle available for macOS 26' "$OUT"; check "real error text shown in summary" $?
grep -q 'Retry:  brew install raylib' "$OUT"; check "retry command shown" $?
grep -q 'skip  jq (already installed)' "$OUT"; check "installed formula skipped" $?
grep -q 'skip  ghostty (already installed)' "$OUT"; check "installed cask skipped" $?
grep -q 'skip  esbenp.prettier-vscode (already installed)' "$OUT"; check "installed extension skipped" $?
grep -qE '^  [0-9]+ installed, [0-9]+ skipped, 1 failed' "$OUT"; check "summary counts printed" $?

grep -qx 'starship' "$STATE/brew-installed"; check "formulae installed" $?
grep -qx 'obsidian' "$STATE/brew-installed"; check "casks installed" $?
grep -qx 'qwtel.sqlite-viewer' "$STATE/ext-installed"; check "extensions installed" $?
grep -qx 'serve' "$STATE/npm-installed" && grep -qx 'nodemon' "$STATE/npm-installed"
check "npm globals installed" $?
[ -f "$STATE/gh-setup-git" ]; check "gh auth setup-git ran" $?

[ "$(git config --global --get init.defaultBranch)" = "main" ]; check "init.defaultBranch=main" $?
[ "$(git config --global --get push.autoSetupRemote)" = "true" ]; check "push.autoSetupRemote=true" $?
[ "$(git config --global --get pull.rebase)" = "false" ]; check "pull.rebase=false" $?
grep -qxF '# >>> machine-setup >>>' "$HOME/.zshrc"; check "~/.zshrc block written" $?
ls "$HOME/Library/Logs/machine-setup/"install-*.log >/dev/null 2>&1; check "log file written" $?
grep -q 'Log: ' "$OUT"; check "log path printed on the last line" $?
grep -q 'colima start' "$OUT"; check "the three next steps printed" $?

echo "== §14.3 re-run asks nothing and installs nothing"
cp "$HOME/.zshrc" "$WORK/zshrc-before"
rm -f "$STATE/brew-installed" "$STATE/npm-installed" "$STATE/ext-installed"
# Now pretend everything landed, so the second run should be a pure no-op.
cat > "$FAKE/bin/brew" <<STUB
#!/bin/bash
# Real commands may read stdin. If install.sh hands a loop's own stdin to the
# command it invokes, that command drains the list and the loop ends early —
# the bug that stopped a real run three packages in. Draining stdin here keeps
# the suite honest about it.
cat > /dev/null 2>&1
case "\$1 \$2" in "shellenv "*) echo 'export HOMEBREW_PREFIX="$FAKE"'; echo 'export PATH="$FAKE/bin:\$PATH"'; exit 0 ;; esac
if [ "\$1" = "list" ]; then
  [ "\$2" = "--formula" ] && sed -E -n 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' "$REPO/Brewfile"
  [ "\$2" = "--cask" ] && sed -E -n 's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/p' "$REPO/Brewfile"
  exit 0
fi
[ "\$1" = "install" ] && { echo "\${!#}" >> "$STATE/brew-installed"; exit 0; }
exit 0
STUB
cat > "$FAKE/bin/code" <<STUB
#!/bin/bash
# Real commands may read stdin. If install.sh hands a loop's own stdin to the
# command it invokes, that command drains the list and the loop ends early —
# the bug that stopped a real run three packages in. Draining stdin here keeps
# the suite honest about it.
cat > /dev/null 2>&1
[ "\$1" = "--list-extensions" ] && { sed -E -n 's/^[[:space:]]*vscode[[:space:]]+"([^"]+)".*/\1/p' "$REPO/Brewfile"; exit 0; }
[ "\$1" = "--install-extension" ] && { echo "\$2" >> "$STATE/ext-installed"; exit 0; }
exit 0
STUB
cat > "$FAKE/bin/npm" <<'STUB'
#!/bin/bash
# Real commands may read stdin. If install.sh hands a loop's own stdin to the
# command it invokes, that command drains the list and the loop ends early —
# the bug that stopped a real run three packages in. Draining stdin here keeps
# the suite honest about it.
cat > /dev/null 2>&1
[ "$1" = "ls" ] && { echo "/x/serve"; echo "/x/nodemon"; exit 0; }
exit 0
STUB
chmod +x "$FAKE"/bin/*

OUT2="$WORK/run2.txt"
"$WORK/install.sh" > "$OUT2" 2>&1 < /dev/null
STATUS2=$?
[ "$STATUS2" -eq 0 ]; check "exit code 0 on a clean re-run" $?
[ ! -f "$STATE/brew-installed" ]; check "installed nothing via brew" $?
[ ! -f "$STATE/npm-installed" ]; check "installed no npm packages" $?
[ ! -f "$STATE/ext-installed" ]; check "installed no extensions" $?
cmp -s "$WORK/zshrc-before" "$HOME/.zshrc"; check "~/.zshrc byte-identical" $?
grep -qE '^  0 installed, [0-9]+ skipped, 0 failed' "$OUT2"; check "summary says 0 installed, 0 failed" $?
! grep -q 'FAILED' "$OUT2"; check "no FAILED section" $?

echo; echo "$PASS passed, $FAILN failed"; [ "$FAILN" -eq 0 ]
