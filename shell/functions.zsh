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

  # A branch that has never been pushed needs its upstream set. Done here rather
  # than relying on push.autoSetupRemote so gacp works on any machine.
  if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    git push
  else
    git push -u origin HEAD
  fi
}
