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

print ""
print "$PASS passed, $FAILN failed"
[[ $FAILN -eq 0 ]]
