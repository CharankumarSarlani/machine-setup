#!/bin/zsh
# §14.8 — gacp commits and pushes, setting upstream on a fresh branch.
emulate -L zsh
setopt no_unset

REPO=${0:A:h:h}
WORK=$(mktemp -d)
trap 'rm -rf $WORK' EXIT

PASS=0; FAILN=0
check() { if [[ $2 -eq 0 ]]; then ((PASS++)); print "  ok    $1"; else ((FAILN++)); print "  FAIL  $1"; fi }

source $REPO/shell/functions.zsh
source $REPO/shell/aliases.zsh

export HOME=$WORK/home; mkdir -p $HOME
export GIT_CONFIG_GLOBAL=$HOME/.gitconfig
git config --global user.name  "Test User"
git config --global user.email "test@example.com"
git config --global init.defaultBranch main

git init --bare -q $WORK/remote.git
git clone -q $WORK/remote.git $WORK/clone
cd $WORK/clone

print "== fresh branch, first push"
print "hello" > file.txt
gacp initial commit here > $WORK/out 2>&1
check "gacp exited 0" $?
git log -1 --pretty=%s | grep -qx 'initial commit here'; check "message taken from unquoted args" $?
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1
check "upstream set on first push" $?
git -C $WORK/remote.git log -1 --pretty=%s | grep -qx 'initial commit here'
check "commit reached the remote" $?

print "== nothing to commit is not an error"
gacp again > $WORK/out 2>&1
check "gacp exited 0 with nothing staged" $?
grep -q 'nothing to commit' $WORK/out; check "said 'nothing to commit'" $?

print "== default message"
print "more" >> file.txt
gacp > $WORK/out 2>&1
check "gacp with no args exited 0" $?
git log -1 --pretty=%s | grep -qE '^chore: wip [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'
check "default message is 'chore: wip <date> <time>'" $?

print "== second push on an existing branch"
print "third" >> file.txt
gacp third change > $WORK/out 2>&1
check "gacp exited 0" $?
git -C $WORK/remote.git log -1 --pretty=%s | grep -qx 'third change'; check "remote updated" $?

print "== new branch gets its own upstream"
git checkout -q -b feature/thing
print "branchy" > b.txt
gacp on a branch > $WORK/out 2>&1
check "gacp exited 0 on new branch" $?
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null | grep -qx 'origin/feature/thing'
check "upstream is origin/feature/thing" $?

print "== outside a git repo"
cd $WORK
gacp nope > $WORK/out 2>&1
[[ $? -ne 0 ]]; check "gacp fails outside a repo" $?
grep -q 'not a git repository' $WORK/out; check "explains why" $?

print "== gp alias"
[[ $(alias gp) == *'git push'* ]]; check "gp aliases git push" $?

# --- creating the remote when there isn't one --------------------------------
# gh is stubbed: `gh repo create --source=. --remote=origin` really does wire an
# origin up, so point it at a local bare repo and record how it was called.
STUB=$WORK/stub; mkdir -p $STUB
cat > $STUB/gh <<'STUBEOF'
#!/bin/bash
case "$1 $2" in
  "auth status")  exit 0 ;;
  "repo view")    grep -qx "$3" "$GH_EXISTING" 2>/dev/null && {
                    [ "$4" = "--json" ] && echo "file://$GH_REMOTES/$3.git"
                    exit 0
                  }; exit 1 ;;
  "repo create")  echo "$*" >> "$GH_CALLS"
                  name="$3"
                  git init --bare -q "$GH_REMOTES/$name.git"
                  git remote add origin "file://$GH_REMOTES/$name.git"
                  exit 0 ;;
esac
exit 0
STUBEOF
chmod +x $STUB/gh
export PATH=$STUB:$PATH
export GH_REMOTES=$WORK/gh-remotes; mkdir -p $GH_REMOTES
export GH_CALLS=$WORK/gh-calls; : > $GH_CALLS
export GH_EXISTING=$WORK/gh-existing; : > $GH_EXISTING

print "== no origin: creates the GitHub repo and pushes"
mkdir -p $WORK/my-new-project && cd $WORK/my-new-project
git init -q; print "hi" > a.txt
gacp first commit > $WORK/out 2>&1
check "gacp exited 0 with no origin" $?
git remote get-url origin >/dev/null 2>&1; check "origin now exists" $?
grep -q 'repo create my-new-project' $GH_CALLS; check "repo named after the directory" $?
grep -q '\-\-public' $GH_CALLS; check "created public" $?
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1
check "upstream set" $?
git --git-dir=$GH_REMOTES/my-new-project.git log -1 --pretty=%s 2>/dev/null | grep -qx 'first commit'
check "commit reached the new remote" $?

print "== second run does not create it again"
: > $GH_CALLS
print "more" >> a.txt
gacp second commit > $WORK/out 2>&1
check "gacp exited 0" $?
[[ ! -s $GH_CALLS ]]; check "gh repo create was not called again" $?

print "== repo already on GitHub: links instead of creating"
print 'existing-thing' > $GH_EXISTING
git init --bare -q $GH_REMOTES/existing-thing.git
mkdir -p $WORK/existing-thing && cd $WORK/existing-thing
git init -q; print "x" > x.txt
: > $GH_CALLS
gacp hello > $WORK/out 2>&1
check "gacp exited 0" $?
[[ ! -s $GH_CALLS ]]; check "did not try to create a duplicate" $?
grep -q 'linking to existing' $WORK/out; check "said it was linking" $?
git remote get-url origin | grep -q 'existing-thing'; check "origin points at it" $?

print "== directory name with characters GitHub rejects"
mkdir -p "$WORK/my project v2" && cd "$WORK/my project v2"
git init -q; print "y" > y.txt
: > $GH_CALLS
gacp naming > $WORK/out 2>&1
check "gacp exited 0" $?
grep -q 'repo create my-project-v2' $GH_CALLS; check "name sanitised to my-project-v2" $?

print "== run from a subdirectory: named after the git root, not \$PWD"
mkdir -p $WORK/acme-api/src/handlers
cd $WORK/acme-api && git init -q && print "q" > q.txt
cd $WORK/acme-api/src/handlers
: > $GH_CALLS
gacp from a subdir > $WORK/out 2>&1
check "gacp exited 0" $?
grep -q 'repo create acme-api' $GH_CALLS; check "used the git root name (acme-api)" $?
! grep -q 'repo create handlers' $GH_CALLS; check "did not use \$PWD (handlers)" $?

print "== gh missing: fails clearly, commit is kept"
mkdir -p $WORK/no-gh && cd $WORK/no-gh
git init -q; print "z" > z.txt
PATH=/usr/bin:/bin gacp stranded > $WORK/out 2>&1
[[ $? -ne 0 ]]; check "gacp reports failure" $?
grep -q 'gh is not installed' $WORK/out; check "explains gh is missing" $?
[[ -n $(git log -1 --pretty=%s 2>/dev/null) ]]; check "the commit survived locally" $?

print ""
print "$PASS passed, $FAILN failed"
[[ $FAILN -eq 0 ]]
