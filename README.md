# machine-setup

A working macOS development environment, from one command.

```sh
curl -fsSL https://raw.githubusercontent.com/CharankumarSarlani/machine-setup/main/install.sh | bash
```

Then open a new terminal. That's it.

Works on Apple Silicon and Intel.

## What you'll be asked

Four things, at most, and only the ones that apply to your machine:

| Prompt | When |
|---|---|
| Click through macOS's Xcode Command Line Tools dialog | fresh machine only |
| Your Mac password | if an install into `/Applications` needs it |
| Your name and email for git | if they aren't set already |
| GitHub login, which opens a browser | if you aren't logged in already |

## What you get

| | |
|---|---|
| **CLI tools** | git, gh, node, deno, openjdk, sqlite, postgresql@17, colima + docker, jq, bat, tree, htop, pstree, ack, glow, tokei, telnet, watchman, imagemagick, raylib, starship |
| **Apps** | Ghostty, VS Code, IntelliJ IDEA CE, Chrome, Obsidian, Rectangle, Bruno |
| **VS Code** | Prettier, Live Server, SQLite Viewer |
| **Shell** | starship prompt, PATH set up for the keg-only tools, `gacp` and `gp` |
| **Git** | identity configured, `gh` logged in, `git push` works without a password |

The full list lives in [`Brewfile`](Brewfile).

## Two commands worth knowing

```sh
gacp fix login bug   # add, commit and push, in one go — quoting optional
gacp                 # same, with a default message: chore: wip 2026-08-30 14:32
gp                   # git push
```

`gacp` sets the upstream automatically the first time you push a branch. If there's
nothing to commit it says so and stops — that isn't an error.

## Three things to do yourself

The installer prints these at the end, because no script can do them for you:

1. **Open a new terminal.** A script can't change the shell that launched it.
2. **Give Rectangle Accessibility permission** the first time you launch it. macOS
   requires a human to toggle that.
3. **Start Docker and Postgres when you want them.** `colima start` boots a Linux VM —
   minutes and hundreds of megabytes — and neither should be running at every login
   unless you asked for it:
   ```sh
   colima start
   brew services start postgresql@17
   ```

## Updating

Run the same one-liner again. It re-downloads the current configuration, installs
anything new, and skips everything you already have. There is no second command.

## If something fails

One failure doesn't stop the run — the rest still installs. The summary lists what
failed, the real error, and the exact command to retry:

```
==> Summary
  38 installed, 4 skipped, 1 failed

  FAILED
    raylib
      Error: raylib: no bottle available for macOS 26
      Retry:  brew install raylib
```

A full transcript is at `~/Library/Logs/machine-setup/install-<timestamp>.log`, and the
path is printed on the last line of every run. Logs accumulate rather than overwrite.

If your terminal ever misbehaves, `zsh -f` starts a shell that reads no config at all.
Your previous `~/.zshrc` is backed up to
`~/Library/Application Support/machine-setup/backups/` before the first change.

Exit codes: `0` everything worked, `1` stopped before installing anything, `2` finished
but something in the FAILED list needs attention.

---

## For maintainers

**Adding a package is one line in `Brewfile`.** `install.sh` never changes.

```
machine-setup/
├── install.sh         # the only thing curl fetches
├── Brewfile           # every formula, cask and VS Code extension
├── npm-packages.txt   # global npm packages, one per line
├── git/settings.txt   # shared git config, key=value per line
└── shell/
    ├── path.zsh       # brew shellenv, JAVA_HOME, keg-only PATHs
    ├── aliases.zsh    # gp
    └── functions.zsh  # gacp
```

Nothing is cloned onto the target machine. `install.sh` downloads a tarball into a temp
directory, uses it, and deletes it on exit — a tarball also needs no `git`, which doesn't
exist yet on a genuinely fresh Mac. The three `shell/*.zsh` files are concatenated into a
single marked block in `~/.zshrc`, so the split is a maintenance convenience that leaves
no runtime dependency behind.

`~/.zshrc` is only ever edited between its markers:

```
# >>> machine-setup >>>
# <<< machine-setup <<<
```

Everything above and below is left byte-identical.

Flags, for testing — a normal install uses none of them:

```sh
./install.sh --dry-run    # report what would change, change nothing
./install.sh --verbose    # echo every command's output to the console too
./install.sh --help
```

Run `install.sh` from a checkout and it uses the files next to it instead of downloading.
Point it at a fork with `MACHINE_SETUP_REPO=owner/repo` and `MACHINE_SETUP_BRANCH=branch`.

`install.sh` is `shellcheck` clean and written for `/bin/bash`, which on macOS is still
3.2 — no associative arrays, no `mapfile`.
