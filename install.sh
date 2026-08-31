#!/usr/bin/env bash
#
# machine-setup — one command, a working macOS development environment.
#
#   curl -fsSL https://raw.githubusercontent.com/CharankumarSarlani/machine-setup/main/install.sh | bash
#
# Everything is wrapped in main() and called on the last line: under `curl | bash`
# a dropped connection would otherwise run a half-downloaded installer.
# Written for /bin/bash, which on macOS is 3.2 — no associative arrays, no mapfile.

set -uo pipefail

# ---------------------------------------------------------------- configuration

REPO_SLUG="${MACHINE_SETUP_REPO:-CharankumarSarlani/machine-setup}"
REPO_BRANCH="${MACHINE_SETUP_BRANCH:-main}"
TARBALL_URL="https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_BRANCH}"
HOMEBREW_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

MARK_START='# >>> machine-setup >>>'
MARK_END='# <<< machine-setup <<<'

BACKUP_DIR="$HOME/Library/Application Support/machine-setup/backups"
LOG_DIR="$HOME/Library/Logs/machine-setup"

# ---------------------------------------------------------------------- state

DRY_RUN=0
VERBOSE=0
TMP_DIR=""
CONFIG_DIR=""
SCRIPT_DIR=""
LOG_FILE=""
RUN_OUT=""
LAST_ERR=""

N_OK=0
N_SKIP=0
N_FAIL=0
FAIL_NAMES=()
FAIL_CMDS=()
FAIL_ERRS=()

HAVE_FORMULA=""
HAVE_CASK=""
HAVE_EXT=""
EXT_LISTED=0
CODE_BIN=""

C_OFF=""; C_RED=""; C_GREEN=""; C_BLUE=""; C_DIM=""; C_BOLD=""

# --------------------------------------------------------------------- output

setup_colors() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_OFF=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_BLUE=$'\033[34m'
    C_DIM=$'\033[2m'
    C_BOLD=$'\033[1m'
  fi
}

log() {
  [ -n "$LOG_FILE" ] && printf '%s\n' "$*" >>"$LOG_FILE"
  return 0
}

say() {
  printf '%s\n' "$*"
  log "$*"
}

# Print a multi-line string with every line indented, to console and log.
say_block() {
  local indent=$1 line
  printf '%s\n' "$2" | while IFS= read -r line; do
    printf '%s%s\n' "$indent" "$line"
  done
  printf '%s\n' "$2" | while IFS= read -r line; do
    log "${indent}${line}"
  done
}

section() {
  printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_OFF" "$C_BOLD" "$1" "$C_OFF"
  log ""
  log "==> $1"
}

ok() {
  N_OK=$((N_OK + 1))
  printf '  %sok%s    %s\n' "$C_GREEN" "$C_OFF" "$1"
  log "  ok    $1"
}

skip() {
  N_SKIP=$((N_SKIP + 1))
  printf '  %sskip%s  %s\n' "$C_DIM" "$C_OFF" "$1"
  log "  skip  $1"
}

note() {
  printf '  %s%s%s\n' "$C_DIM" "$1" "$C_OFF"
  log "  $1"
}

# fail <name> <retry command> <error text>
fail() {
  N_FAIL=$((N_FAIL + 1))
  FAIL_NAMES+=("$1")
  FAIL_CMDS+=("$2")
  FAIL_ERRS+=("$3")
  printf '  %sFAIL%s  %s\n' "$C_RED" "$C_OFF" "$1"
  log "  FAIL  $1"
  log "$3"
}

die() {
  printf '\n%sError:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2
  log "Error: $*"
  [ -n "$LOG_FILE" ] && printf 'Log: %s\n' "$LOG_FILE" >&2
  exit 1
}

usage() {
  cat <<'EOF'
machine-setup — one command, a working macOS development environment.

Usage:
  curl -fsSL https://raw.githubusercontent.com/CharankumarSarlani/machine-setup/main/install.sh | bash

Options (for maintainers; a normal install needs none of them):
  --dry-run   report what would be installed or changed, change nothing
  --verbose   echo the output of every command to the console as well as the log
  --help      this text

Environment:
  MACHINE_SETUP_REPO     owner/repo to fetch configuration from
  MACHINE_SETUP_BRANCH   branch to fetch (default: main)

Exit codes:
  0  everything worked
  1  stopped before installing anything
  2  finished, but something in the FAILED list needs attention
EOF
}

# --------------------------------------------------------------------- helpers

# Invoked by the EXIT trap, so the temp directory goes away on success, on
# failure, and on Ctrl-C alike.
# shellcheck disable=SC2329
cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

# Run a command, sending its output to the log rather than the console.
# Leaves an excerpt of the output in LAST_ERR for failure reporting.
run() {
  local status
  log "\$ $*"
  "$@" >"$RUN_OUT" 2>&1
  status=$?
  cat "$RUN_OUT" >>"$LOG_FILE"
  if [ "$VERBOSE" -eq 1 ]; then
    sed -E 's/^/        /' "$RUN_OUT"
  fi
  LAST_ERR="$(err_excerpt "$RUN_OUT")"
  return "$status"
}

# The useful part of a failed command's output: its error lines, or the tail.
err_excerpt() {
  local text
  text="$(grep -E -m 3 '^(Error|fatal|Warning: |.*[Ee]rror:)' "$1" 2>/dev/null)"
  if [ -z "$text" ]; then
    text="$(grep -v -E '^[[:space:]]*$' "$1" 2>/dev/null | tail -n 5)"
  fi
  [ -z "$text" ] && text="(no output; see the log)"
  printf '%s' "$text"
}

# Read one non-empty answer from the terminal. Under `curl | bash` stdin is the
# script itself, so a bare `read` would silently consume script text.
ask() {
  local text=$1 answer=""
  while [ -z "$answer" ]; do
    printf '%s' "$text" >/dev/tty
    IFS= read -r answer </dev/tty || return 1
  done
  printf '%s' "$answer"
}

# ------------------------------------------------------------------ preflight

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --verbose) VERBOSE=1 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; printf '\nUnknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
  done
}

preflight() {
  local os arch
  os="$(uname -s)"
  [ "$os" = "Darwin" ] ||
    die "This installer is for macOS. Found $os."

  arch="$(uname -m)"
  case "$arch" in
    arm64 | x86_64) ;;
    *) die "Unsupported architecture $arch. Apple Silicon (arm64) and Intel (x86_64) only." ;;
  esac

  [ "$(id -u)" -ne 0 ] ||
    die "Do not run this as root. Run it as yourself; you will be asked for your password if an install needs it."

  [ -r /dev/tty ] ||
    die "No terminal available. Run this from Terminal, not from a script or a CI job."
}

setup_workspace() {
  mkdir -p "$LOG_DIR" || die "Cannot create $LOG_DIR"
  LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
  : >"$LOG_FILE" || die "Cannot write to $LOG_FILE"

  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/machine-setup.XXXXXX")" ||
    die "Cannot create a temporary directory."
  trap cleanup EXIT
  RUN_OUT="$TMP_DIR/command-output"

  log "machine-setup $(date '+%Y-%m-%d %H:%M:%S')"
  log "macOS $(sw_vers -productVersion 2>/dev/null) on $(uname -m)"
  log "repo ${REPO_SLUG}@${REPO_BRANCH}, dry-run=${DRY_RUN}"

  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
}

# ------------------------------------------------------------------ the steps

ensure_clt() {
  section "Xcode Command Line Tools"

  if xcode-select -p >/dev/null 2>&1; then
    skip "Xcode Command Line Tools (already installed)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would run xcode-select --install"
    return 0
  fi

  note "macOS will now show its own dialog. Click Install and accept the licence."
  xcode-select --install >>"$LOG_FILE" 2>&1

  local waited=0
  while ! xcode-select -p >/dev/null 2>&1; do
    sleep 5
    waited=$((waited + 5))
    if [ $((waited % 60)) -eq 0 ]; then
      note "still waiting for the Command Line Tools ($((waited / 60)) min)"
    fi
    if [ "$waited" -ge 1800 ]; then
      die "The Command Line Tools did not finish installing. Run 'xcode-select --install' by hand, then re-run this installer."
    fi
  done
  ok "Xcode Command Line Tools"
}

# Put brew on PATH if it is installed. Returns non-zero if it is not.
load_homebrew() {
  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      eval "$("$candidate" shellenv)"
      return 0
    fi
  done
  command -v brew >/dev/null 2>&1
}

ensure_homebrew() {
  section "Homebrew"

  if load_homebrew; then
    skip "Homebrew (already installed)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would install Homebrew"
    return 0
  fi

  local installer="$TMP_DIR/homebrew-install.sh"
  curl -fsSL "$HOMEBREW_INSTALLER_URL" -o "$installer" ||
    die "Could not download the Homebrew installer from $HOMEBREW_INSTALLER_URL"

  # Homebrew needs sudo to create its prefix, but NONINTERACTIVE=1 makes it run
  # `sudo -n`, which never prompts — so it aborts with "needs to be an
  # Administrator" even for an admin user. Take the password here instead: that
  # caches the sudo timestamp, and Homebrew's own check then passes silently.
  if ! sudo -n true 2>/dev/null; then
    note "Homebrew needs your Mac password to install itself."
    # No redirect needed: sudo reads the password from the terminal itself,
    # not from stdin, which under curl | bash is the script.
    if ! sudo -v; then
      die "Homebrew needs administrator access to install. Your account must be able to run sudo."
    fi
  fi

  # Shown on the console, not just logged: this step is slow and worth watching.
  NONINTERACTIVE=1 /bin/bash "$installer" </dev/tty 2>&1 | tee -a "$LOG_FILE"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    die "Homebrew failed to install. See the log for the full output."
  fi

  load_homebrew || die "Homebrew installed but 'brew' is still not on PATH."
  ok "Homebrew"
}

fetch_config() {
  section "Configuration"

  # Maintainer path: install.sh sitting next to the config files uses them
  # directly. Never true for the curl | bash install.
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/Brewfile" ]; then
    CONFIG_DIR="$SCRIPT_DIR"
    skip "configuration (using the checkout at $SCRIPT_DIR)"
    return 0
  fi

  CONFIG_DIR="$TMP_DIR/config"
  mkdir -p "$CONFIG_DIR" || die "Cannot create $CONFIG_DIR"

  if ! curl -fsSL "$TARBALL_URL" | tar -xz --strip-components=1 -C "$CONFIG_DIR" 2>>"$LOG_FILE"; then
    die "Could not download the configuration from $TARBALL_URL"
  fi
  [ -f "$CONFIG_DIR/Brewfile" ] ||
    die "The downloaded configuration has no Brewfile. Check $TARBALL_URL"

  ok "configuration downloaded"
}

# Standard Brewfile syntax in, "<kind> <name>" per line out.
# sed -E because BSD sed's basic regex has no alternation.
parse_brewfile() {
  sed -E -n 's/^[[:space:]]*(brew|cask|vscode)[[:space:]]+"([^"]+)".*/\1 \2/p' "$1"
}

find_code() {
  local bundled="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  if command -v code >/dev/null 2>&1; then
    command -v code
  elif [ -x "$bundled" ]; then
    printf '%s' "$bundled"
  fi
}

install_formula() {
  local name=$1 base
  base="${name##*/}"

  if printf '%s\n' "$HAVE_FORMULA" | grep -qx -- "$base"; then
    skip "$name (already installed)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would install $name"
    return 0
  fi
  if run brew install --formula "$name"; then
    ok "$name"
  else
    fail "$name" "brew install $name" "$LAST_ERR"
  fi
}

install_cask() {
  local name=$1 base
  base="${name##*/}"

  if printf '%s\n' "$HAVE_CASK" | grep -qx -- "$base"; then
    skip "$name (already installed)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would install $name"
    return 0
  fi
  # --adopt takes ownership of an app already sitting in /Applications from a
  # manual download, instead of failing outright. It compares bundle versions
  # first and refuses if they differ, so it never overwrites anything — unlike
  # --force, which deletes the existing app.
  if run brew install --cask --adopt "$name"; then
    ok "$name"
  else
    fail "$name" "brew install --cask --adopt $name" "$LAST_ERR"
  fi
}

install_vscode_ext() {
  local name=$1 lower

  if [ -z "$CODE_BIN" ]; then
    CODE_BIN="$(find_code)"
  fi
  if [ -z "$CODE_BIN" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note "would install $name (once VS Code is installed)"
      return 0
    fi
    fail "$name" "code --install-extension $name" \
      "The 'code' command was not found, so the VS Code extension could not be installed."
    return 0
  fi

  if [ "$EXT_LISTED" -eq 0 ]; then
    HAVE_EXT="$("$CODE_BIN" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    EXT_LISTED=1
  fi

  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  if printf '%s\n' "$HAVE_EXT" | grep -qx -- "$lower"; then
    skip "$name (already installed)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would install $name"
    return 0
  fi
  if run "$CODE_BIN" --install-extension "$name" --force; then
    ok "$name"
  else
    fail "$name" "code --install-extension $name" "$LAST_ERR"
  fi
}

install_packages() {
  section "Packages"

  local brewfile="$CONFIG_DIR/Brewfile"
  if [ ! -f "$brewfile" ]; then
    fail "Brewfile" "re-run the installer" "No Brewfile in $CONFIG_DIR"
    return 0
  fi

  HAVE_FORMULA="$(brew list --formula -1 2>/dev/null)"
  HAVE_CASK="$(brew list --cask -1 2>/dev/null)"

  local kind name
  while read -r kind name; do
    [ -n "$kind" ] || continue
    case "$kind" in
      brew) install_formula "$name" ;;
      cask) install_cask "$name" ;;
      vscode) install_vscode_ext "$name" ;;
    esac
  done <<EOF
$(parse_brewfile "$brewfile")
EOF
}

install_npm_packages() {
  section "npm globals"

  local list="$CONFIG_DIR/npm-packages.txt"
  if [ ! -f "$list" ]; then
    skip "npm-packages.txt (not in the configuration)"
    return 0
  fi
  if ! command -v npm >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note "would install npm packages (once node is installed)"
      return 0
    fi
    fail "npm packages" "brew install node" "npm was not found, so the node formula did not install."
    return 0
  fi

  local have pkg
  have="$(npm ls -g --depth=0 --parseable 2>/dev/null | sed -E 's#^.*/##')"

  while IFS= read -r pkg; do
    pkg="$(printf '%s' "$pkg" | tr -d '[:space:]')"
    case "$pkg" in '' | \#*) continue ;; esac

    if printf '%s\n' "$have" | grep -qx -- "$pkg"; then
      skip "$pkg (already installed)"
      continue
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      note "would install $pkg"
      continue
    fi
    if run npm install -g "$pkg"; then
      ok "$pkg"
    else
      fail "$pkg" "npm install -g $pkg" "$LAST_ERR"
    fi
  done <"$list"
}

# Concatenate shell/*.zsh into one self-contained block. Resolving the split
# here is what lets the repo be deleted afterwards.
build_shell_block() {
  local target=$1 part
  {
    printf '%s\n' "$MARK_START"
    printf '%s\n' "#   generated by machine-setup — edits between these markers are replaced on the next run"
    for part in path.zsh aliases.zsh functions.zsh; do
      if [ -f "$CONFIG_DIR/shell/$part" ]; then
        printf '\n'
        cat "$CONFIG_DIR/shell/$part"
      fi
    done
    printf '%s\n' "$MARK_END"
  } >"$target"
}

# The "~/.zshrc" strings below are labels shown to the user, not paths.
# shellcheck disable=SC2088
configure_shell() {
  section "Shell"

  local rc="$HOME/.zshrc"
  local block="$TMP_DIR/zshrc-block"
  local new="$TMP_DIR/zshrc-new"

  build_shell_block "$block"

  if [ ! -f "$rc" ]; then
    cp "$block" "$new"
  elif grep -qxF "$MARK_START" "$rc"; then
    # Replace between the markers in place, leaving every other byte alone.
    awk -v start="$MARK_START" -v end="$MARK_END" -v blockfile="$block" '
      function emit(   line) { while ((getline line < blockfile) > 0) print line; close(blockfile) }
      $0 == start        { emit(); inside = 1; next }
      inside && $0 == end { inside = 0; next }
      inside             { next }
                         { print }
    ' "$rc" >"$new"
  else
    {
      cat "$rc"
      # A file with no trailing newline would otherwise glue onto our marker.
      [ -n "$(tail -c 1 "$rc")" ] && printf '\n'
      printf '\n'
      cat "$block"
    } >"$new"
  fi

  if cmp -s "$rc" "$new" 2>/dev/null; then
    skip "~/.zshrc (already up to date)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would update the machine-setup block in ~/.zshrc"
    return 0
  fi

  if [ -f "$rc" ]; then
    if mkdir -p "$BACKUP_DIR" && cp "$rc" "$BACKUP_DIR/zshrc-$(date +%Y%m%d-%H%M%S)"; then
      note "backed up ~/.zshrc to $BACKUP_DIR"
    else
      fail "~/.zshrc backup" "cp ~/.zshrc ~/.zshrc.bak" \
        "Could not write a backup to $BACKUP_DIR, so ~/.zshrc was left alone."
      return 0
    fi
  fi

  if cp "$new" "$rc"; then
    ok "~/.zshrc"
  else
    fail "~/.zshrc" "re-run the installer" "Could not write to $rc"
  fi
}

configure_git() {
  section "Git"

  local settings="$CONFIG_DIR/git/settings.txt"
  local line key value current

  if [ -f "$settings" ]; then
    while IFS= read -r line; do
      case "$line" in '' | \#*) continue ;; esac
      case "$line" in *=*) ;; *) continue ;; esac
      key="${line%%=*}"
      value="${line#*=}"
      [ -n "$key" ] || continue

      current="$(git config --global --get "$key" 2>/dev/null)"
      if [ -n "$current" ]; then
        skip "$key (already $current)"
        continue
      fi
      if [ "$DRY_RUN" -eq 1 ]; then
        note "would set $key=$value"
        continue
      fi
      if run git config --global "$key" "$value"; then
        ok "$key=$value"
      else
        fail "git $key" "git config --global $key $value" "$LAST_ERR"
      fi
    done <"$settings"
  fi

  configure_git_identity
}

# Identity is prompted for, never kept in the repo, so the repo stays publishable.
configure_git_identity() {
  local name email

  name="$(git config --global --get user.name 2>/dev/null)"
  if [ -n "$name" ]; then
    skip "user.name (already $name)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    note "would ask for your git name"
  else
    name="$(ask '  Your name, for git commits: ')" || die "Could not read from the terminal."
    if run git config --global user.name "$name"; then
      ok "user.name=$name"
    else
      fail "user.name" "git config --global user.name '$name'" "$LAST_ERR"
    fi
  fi

  email="$(git config --global --get user.email 2>/dev/null)"
  if [ -n "$email" ]; then
    skip "user.email (already $email)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    note "would ask for your git email"
  else
    while :; do
      email="$(ask '  Your email, for git commits: ')" || die "Could not read from the terminal."
      case "$email" in
        ?*@?*.?*) break ;;
        *) printf '  That does not look like an email address.\n' >/dev/tty ;;
      esac
    done
    if run git config --global user.email "$email"; then
      ok "user.email=$email"
    else
      fail "user.email" "git config --global user.email '$email'" "$LAST_ERR"
    fi
  fi
}

configure_github() {
  section "GitHub"

  if ! command -v gh >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note "would log in to GitHub (once gh is installed)"
      return 0
    fi
    fail "gh auth" "gh auth login && gh auth setup-git" \
      "The gh command was not found, so GitHub could not be set up."
    return 0
  fi

  if gh auth status >/dev/null 2>&1; then
    skip "gh auth (already logged in)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    note "would run gh auth login"
    return 0
  else
    note "A browser window will open so you can log in to GitHub."
    log "\$ gh auth login --hostname github.com --git-protocol https --web"
    # Not redirected: gh prints a one-time code the user has to read.
    if gh auth login --hostname github.com --git-protocol https --web </dev/tty; then
      ok "gh auth"
    else
      fail "gh auth" "gh auth login" \
        "gh auth login did not complete. Without it, git push to a private repo will ask for a password."
      return 0
    fi
  fi

  # Makes gh the git credential helper, so `git push` never asks for a password.
  # gh writes itself in as a credential.<host>.helper; finding one means it is
  # already done, and a re-run should report nothing.
  if git config --global --get-regexp '^credential\.' 2>/dev/null | grep -q 'gh auth git-credential'; then
    skip "git credentials via gh (already configured)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would run gh auth setup-git"
    return 0
  fi
  if run gh auth setup-git; then
    ok "git credentials via gh"
  else
    fail "gh auth setup-git" "gh auth setup-git" "$LAST_ERR"
  fi
}

summary() {
  section "Summary"
  say "  $N_OK installed, $N_SKIP skipped, $N_FAIL failed"

  if [ "$N_FAIL" -gt 0 ]; then
    printf '\n  %sFAILED%s\n' "$C_RED" "$C_OFF"
    log ""
    log "  FAILED"
    local i=0
    while [ "$i" -lt "${#FAIL_NAMES[@]}" ]; do
      say "    ${FAIL_NAMES[$i]}"
      say_block "      " "${FAIL_ERRS[$i]}"
      say "      Retry:  ${FAIL_CMDS[$i]}"
      i=$((i + 1))
    done
  fi

  printf '\n  %sNEXT%s\n' "$C_BOLD" "$C_OFF"
  log ""
  log "  NEXT"
  say "    1. Open a new terminal — this one cannot pick up the shell changes."
  say "    2. Rectangle asks for Accessibility permission the first time you launch it."
  say "    3. Start the services you need, when you need them:"
  say "         colima start"
  say "         brew services start postgresql@17"

  printf '\n'
  say "  Log: $LOG_FILE"
}

# ------------------------------------------------------------------------ main

main() {
  setup_colors
  parse_args "$@"
  preflight
  setup_workspace

  printf '%smachine-setup%s — macOS development environment\n' "$C_BOLD" "$C_OFF"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%sdry run: nothing will be installed or changed%s\n' "$C_DIM" "$C_OFF"
  fi

  ensure_clt
  ensure_homebrew
  fetch_config
  install_packages
  install_npm_packages
  configure_shell
  configure_git
  configure_github
  summary

  [ "$N_FAIL" -eq 0 ] || exit 2
  exit 0
}

main "$@"
