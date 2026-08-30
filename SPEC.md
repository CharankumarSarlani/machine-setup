# SPEC — macOS machine setup

## 1. The principle

**The intern interacts with one command and a small number of meaningful prompts.
Everything else is implementation detail.**



Which means, explicitly:

- No git clone.
- No manual `brew bundle`.
- No manual config downloads.
- No package-selection menus.
- No repository left behind on their machine.

Anything the installer needs, it fetches, uses, and cleans up. The intern never learns it
existed.

## 2. What a user does

On a brand-new Mac, open Terminal and run one line:

```sh
curl -fsSL https://raw.githubusercontent.com/<user>/machine-setup/main/install.sh | bash
```

They will be asked for, in total:

| Prompt | When |
|---|---|
| Click through macOS's Xcode Command Line Tools dialog | fresh machine only |
| Mac password | if a `/Applications` install needs it |
| Git name and email | if not already configured |
| GitHub login (opens browser) | if not already logged in |

Then open a new terminal. Done.

Works on Apple Silicon and Intel.

## 3. What they get

| | |
|---|---|
| **CLI tools** | git, node, deno, jdk, sqlite, postgres, docker (via colima), gh, jq, bat, tree, htop, and the rest of §6 |
| **Apps** | Ghostty, VS Code, IntelliJ IDEA CE, Chrome, Obsidian, Rectangle, Bruno |
| **VS Code** | Prettier, Live Server, Code Spell Checker, SQLite Viewer |
| **Shell** | starship prompt, correct PATH for the keg-only tools, `gacp` and `gp` |
| **Git** | identity configured, `gh` logged in, `git push` works without asking for a password |

## 4. How it works

1. **Check** — macOS? `arm64` or `x86_64`? Not root? Otherwise stop with a clear message.
2. **Xcode Command Line Tools** — `xcode-select --install` if missing. macOS shows its own
   dialog. This is also where the system `git` comes from.
3. **Homebrew** — official installer, `NONINTERACTIVE=1`.
4. **Download the configuration** — one tarball of the setup repo into a temp directory.
   Used during the run, deleted when it ends. **Never cloned, never left behind.**
5. **Packages** — install everything in `Brewfile`: formulae, casks, VS Code extensions.
   Skip what's present.
6. **npm globals** — everything in `npm-packages.txt`.
7. **Shell** — write the config into `~/.zshrc` between markers (§7).
8. **Git** — apply the shared settings, then ask for name and email if unset (§8).
9. **GitHub** — `gh auth login` if not already authenticated, then `gh auth setup-git`.
10. **Summary** — what was installed, what failed, what's left.

### Why a tarball and not a clone

The configuration files are needed **during** the install, not after. Once §7 has written
the shell config into `~/.zshrc` and §8 has applied the git settings, nothing on the
machine refers back to them. So there is nothing to keep.

A tarball also needs no `git`, which removes a chicken-and-egg problem: on a genuinely
fresh Mac, `git` doesn't exist until step 2 finishes.

**To update:** re-run the same one-liner. It re-downloads the current configuration and
re-applies it. There is no second command to learn.

### Design rules

- **Re-runnable.** Running it twice changes nothing and asks nothing.
- **Never destructive.** It edits `~/.zshrc` between its own markers and backs it up first.
  Everything else in the file is untouched.
- **A failure doesn't stop the run.** The rest still installs; failures are listed at the
  end with the command to retry.
- **Nothing left for afterwards** except the three items in §10.

## 5. Repo layout

This is the maintainer's view. The intern never sees it.

```
machine-setup/
├── README.md            # the one-liner + what it installs
├── install.sh           # the only thing curl fetches
├── Brewfile             # every formula, cask, and VS Code extension
├── npm-packages.txt     # global npm packages, one per line
├── git/
│   └── settings.txt     # shared git config, key=value per line
└── shell/
    ├── path.zsh         # brew shellenv, JAVA_HOME, keg-only PATHs
    ├── aliases.zsh      # gp
    └── functions.zsh    # gacp
```

**Adding a package is a line in `Brewfile`. `install.sh` never changes.**

The `shell/` split is for whoever maintains this repo. At install time the three files are
concatenated into one block in `~/.zshrc` — modularity is resolved during the install and
leaves no runtime dependency. Delete every trace of the repo and the intern's shell still
works.

## 6. Brewfile

Standard Brewfile syntax, so `brew bundle --file=Brewfile` also works by hand:

```ruby
# Core
brew "git"
brew "gh"

# Languages & runtimes
brew "node"
brew "deno"
brew "openjdk"

# Databases
brew "sqlite"
brew "postgresql@17"

# Containers — colima, not Docker Desktop
brew "colima"
brew "docker"
brew "docker-compose"
brew "docker-buildx"

# Tools
brew "jq"
brew "bat"
brew "tree"
brew "htop"
brew "pstree"
brew "ack"
brew "glow"
brew "tokei"
brew "telnet"
brew "watchman"
brew "imagemagick"
brew "raylib"
brew "starship"

# Apps
cask "ghostty"
cask "visual-studio-code"
cask "intellij-idea-ce"
cask "google-chrome"
cask "obsidian"
cask "rectangle"
cask "bruno"

# VS Code extensions
vscode "esbenp.prettier-vscode"
vscode "ritwickdey.LiveServer"
vscode "streetsidesoftware.code-spell-checker"
vscode "qwtel.sqlite-viewer"
```

All names verified against Homebrew as of 2026-08-29.

`brew "git"` is included even though Xcode CLT provides one — Apple's is typically a year
or more behind.

Two other deliberate choices: **`intellij-idea-ce`** is the free Community Edition
(`intellij-idea` is Ultimate and needs a licence), and **`postgresql@17`** is pinned so a
future `brew upgrade` can't silently move you to a new major version.

`npm-packages.txt`:

```
serve
nodemon
```

## 7. Shell config

The installer writes the contents of `shell/path.zsh`, `shell/aliases.zsh`, and
`shell/functions.zsh` into `~/.zshrc`, between markers:

```sh
# >>> machine-setup >>>
#   generated — edits here are replaced on the next run
eval "/opt/homebrew/bin/brew shellenv"
export JAVA_HOME=...
path=(...)
eval "$(starship init zsh)"
alias gp='git push'
gacp() { ... }
# <<< machine-setup <<<
```

Self-contained. Nothing is sourced from another directory, so nothing can go missing.

- No `~/.zshrc` → create it.
- Markers absent → append.
- Markers present → replace what's between them, leaving the rest byte-identical.
- Backed up to `~/Library/Application Support/machine-setup/backups/` before the first write.

`shell/path.zsh` exists because three brew packages are **keg-only** — installing them
doesn't put them on PATH. Without it, `java`, `sqlite3`, and `psql` wouldn't exist as
commands even though they're installed.

Nothing shadows an existing command — no `alias cat=bat`.

## 8. Git setup

`git/settings.txt` holds what's the same for everyone:

```
init.defaultBranch=main
pull.rebase=false
push.autoSetupRemote=true
```

Applied with `git config --global`, only where the key isn't already set.

**Identity is not in the repo.** Name and email are prompted for and written to
`~/.gitconfig`, so the repo stays publishable and personal details stay local. Already
configured → not asked.

## 9. When something goes wrong

### While it's running

```
==> Packages
  ok    node
  skip  jq (already installed)
  FAIL  raylib
```

### At the end

```
==> Summary
  38 installed, 4 skipped, 1 failed

  FAILED
    raylib
      Error: raylib: no bottle available for macOS 26
      Retry:  brew install raylib

  Log: ~/Library/Logs/machine-setup/install-20260830-142150.log
```

Every failure shows **the real error text**, not just the name, plus the exact command to
retry it.

### The log

Full transcript at `~/Library/Logs/machine-setup/install-<timestamp>.log`, including the
brew output too noisy for the console. Path printed on the last line of every run. Logs
accumulate rather than overwrite.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | everything worked |
| 1 | stopped before installing anything — wrong OS, no terminal, Homebrew or download failed |
| 2 | finished, but something in the FAILED list needs attention |

### Fixing one thing

Failures print the exact retry command — usually `brew install <name>`. Run that. Or re-run
the one-liner; it skips everything already installed.

### If the terminal breaks

`~/.zshrc` is backed up before the first write. To get a working shell regardless:
`zsh -f` reads no config at all.

## 10. What's left afterwards

Three things, each because automating it is impossible or worse than not:

1. **Open a new terminal.** A script cannot change the environment of the shell that
   launched it.
2. **Rectangle will ask for Accessibility permission** on first launch. macOS requires a
   human toggle; no script can grant it.
3. **`colima start` and `brew services start postgresql@17`** when wanted. Starting colima
   downloads and boots a Linux VM — minutes and hundreds of megabytes — and a database
   daemon running at every login shouldn't be enabled on someone's behalf.

The installer prints these three and nothing else.

## 11. Convenience commands

### `gacp [message]` — add, commit, push

```sh
gacp fix login bug        # quoting optional
gacp                      # defaults to: chore: wip 2026-08-30 14:32
```

Stages everything, commits, pushes, setting upstream automatically on a branch's first
push. Nothing to commit → says so and stops; that isn't an error.

No confirmation on `main`. Intentional.

If the push fails the commit stays local; the retry is a plain `gp`.

### `gp` — `git push`

## 12. Implementation notes

- **Wrap everything in `main() { ... }` and call `main "$@"` on the last line.**
  `curl | bash` executes lines as they arrive, so a dropped connection would otherwise
  leave a half-run installer. With the wrapper, a truncated download never reaches the call.
- **Prompts must read from `/dev/tty`, not stdin.** Under `curl | bash`, stdin is the
  script itself; a bare `read` silently eats script text.
- **The URL must be `raw.githubusercontent.com`.** A `github.com/...` URL returns HTML. It
  caches ~5 minutes after a push.
- **`sed -E`, not `sed`.** BSD sed on macOS lacks `\|` alternation in basic regex and fails
  by matching nothing rather than erroring.
- **The temp directory is removed by an `EXIT` trap**, so it goes away on success, failure,
  or Ctrl-C.
- `set -uo pipefail`, but **not** `set -e` — a failed package must not abort the run.
- Flags, for maintainers: `--dry-run`, `--verbose`, `--help`. Interns use none of them.
- `shellcheck` clean.

## 13. Out of scope

Docker Desktop, maven/gradle, version managers (nvm/mise), macOS `defaults` tweaks, VS Code
`settings.json`, starting services, an uninstall command.

## 14. Done when

1. On a clean Mac, one command produces a working environment, asking only the four things
   in §2.
2. Nothing from the setup repo remains on the machine afterwards.
3. Re-running asks nothing, installs nothing, and leaves `~/.zshrc` unchanged.
4. Hand-edits above and below the markers survive a re-run.
5. In a new terminal, `git`, `java`, `psql`, `sqlite3`, and `starship` all resolve to the
   brew copies.
6. `git push` to a private repo works without a password prompt.
7. Adding a package is a one-line edit to `Brewfile`, with no change to `install.sh`.
8. `gacp test message` commits and pushes, setting upstream on a fresh branch.
9. A truncated download does nothing at all.
