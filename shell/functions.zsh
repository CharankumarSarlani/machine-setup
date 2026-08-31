# Make sure the repository has an `origin` to push to, creating it on GitHub the
# first time if it has none. Named after the repository's own directory — the
# git root, so running this from a subdirectory still uses the project name.
#
# New repos are created PUBLIC, so whatever is committed becomes world-readable
# the moment it is pushed. Use `gh repo create` by hand for anything private.
_gacp_ensure_remote() {
  git remote get-url origin >/dev/null 2>&1 && return 0

  if ! command -v gh >/dev/null 2>&1; then
    print -u2 "gacp: there is no 'origin' remote, and gh is not installed to create one."
    print -u2 "      brew install gh"
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    print -u2 "gacp: there is no 'origin' remote, and gh is not logged in."
    print -u2 "      gh auth login"
    return 1
  fi

  local root name
  root=$(git rev-parse --show-toplevel) || return 1
  name=${root:t}
  # GitHub accepts letters, digits, dot, dash and underscore. Map anything else
  # to a dash, then tidy up the runs and edges that leaves behind.
  name=${name//[^a-zA-Z0-9._-]/-}
  while [[ $name == *--* ]]; do name=${name//--/-}; done
  name=${name#-}
  name=${name%-}
  if [[ -z $name ]]; then
    print -u2 "gacp: could not work out a repository name from $root"
    return 1
  fi

  # It may already exist on GitHub from an earlier attempt that failed before
  # the remote was wired up. Link to it rather than trying to create it twice.
  if gh repo view "$name" >/dev/null 2>&1; then
    print "gacp: linking to existing GitHub repo $name"
    git remote add origin "$(gh repo view "$name" --json url --jq .url)" || return 1
  else
    print "gacp: creating public GitHub repo $name"
    gh repo create "$name" --public --source=. --remote=origin || return 1
  fi
}

# gacp [message] — stage everything, commit, push.
# Quoting the message is optional: gacp fix login bug
# With no message, commits as: chore: wip <date> <time>
gacp() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    print -u2 "gacp: not a git repository"
    return 1
  fi

  local msg
  if (( $# )); then
    msg="$*"
  else
    msg="chore: wip $(date '+%Y-%m-%d %H:%M')"
  fi

  git add -A || return 1

  # Nothing staged is not an error — it is the normal "already committed" case.
  if git diff --cached --quiet; then
    print "gacp: nothing to commit"
    return 0
  fi

  git commit -m "$msg" || return 1

  # Done after the commit: creating a remote for a repo with no commits is not
  # useful, and this way a failure here still leaves the work committed locally.
  _gacp_ensure_remote || return 1

  # A branch that has never been pushed needs its upstream set. Done here rather
  # than relying on push.autoSetupRemote so gacp works on any machine.
  if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    git push
  else
    git push -u origin HEAD
  fi
}
