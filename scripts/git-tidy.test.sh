#!/usr/bin/env bash
# Scenario test for ~/.claude/scripts/git-tidy.sh against throwaway repos.
set -u
SCRIPT=${SCRIPT:-$HOME/.claude/scripts/git-tidy.sh}
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/git-tidy-test.XXXXXX")
ROOT=$(cygpath -m "$ROOT" 2>/dev/null || echo "$ROOT") # match git's worktree paths
trap 'rm -rf "$ROOT"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
g() { git -c core.autocrlf=false -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

cd "$ROOT"
g init -q --bare origin.git
g clone -q origin.git main 2>/dev/null
cd main
printf 'node_modules/\n' >.gitignore
g add .gitignore && g commit -qm init && g push -q origin main
g remote set-head origin main
base=$(git rev-parse HEAD)

# Branch with one commit, pushed with upstream, merged into origin/main
# (squash-style), then deleted on the remote.
merged_gone() {
  g switch -qc "$1" main
  echo "$1" >"$1.txt" && g add "$1.txt" && g commit -qm "$1"
  g push -qu origin "$1"
  g switch -q main && g merge -q --squash "$1" && g commit -qm "squash $1" && g push -q origin main
  g push -q origin --delete "$1"
}
wt() { g worktree add -q "$ROOT/wt-$1" "$1"; }

merged_gone clean && wt clean
mkdir -p "$ROOT/wt-clean/node_modules/x" && touch "$ROOT/wt-clean/node_modules/x/f"
merged_gone dirty && wt dirty && echo change >>"$ROOT/wt-dirty/dirty.txt"
merged_gone untracked && wt untracked && touch "$ROOT/wt-untracked/new.txt"
merged_gone locked && wt locked && g worktree lock "$ROOT/wt-locked"
merged_gone stale && wt stale && rm -rf "$ROOT/wt-stale"

# Pushed, remote deleted, but never merged.
g switch -qc unmerged main && echo u >u.txt && g add u.txt && g commit -qm u
g push -qu origin unmerged && g push -q origin --delete unmerged && g switch -q main
wt unmerged
# Merged but the remote branch still exists.
g switch -qc live main && g push -qu origin live && g switch -q main && wt live

# Never-pushed agent branches.
g branch worktree-agent-done main
g switch -qc worktree-agent-work main && echo w >w.txt && g add w.txt && g commit -qm w && g switch -q main
g worktree add -q -b worktree-agent-active "$ROOT/wt-active" main
# A never-pushed branch of the user's own.
g branch mine main
g reset -q --hard "$base" # local main lags, as after merging on the remote

out=$(bash "$SCRIPT")
has() { git show-ref --verify --quiet "refs/heads/$1"; }
listed() { git worktree list --porcelain | grep -qxF "worktree $ROOT/wt-$1"; }

check "clean merged worktree removed" "! [ -d '$ROOT/wt-clean' ] && ! listed clean"
check "its branch deleted" "! has clean"
check "dirty worktree kept" "[ -d '$ROOT/wt-dirty' ] && has dirty"
check "untracked worktree kept" "[ -f '$ROOT/wt-untracked/new.txt' ] && has untracked"
check "locked worktree kept" "[ -d '$ROOT/wt-locked' ] && has locked"
check "stale worktree record pruned" "! listed stale && ! has stale"
check "unmerged worktree kept" "[ -d '$ROOT/wt-unmerged' ] && has unmerged"
check "worktree with live remote kept" "[ -d '$ROOT/wt-live' ] && has live"
check "merged agent branch deleted" "! has worktree-agent-done"
check "unmerged agent branch kept" "has worktree-agent-work"
check "checked-out agent branch and worktree kept" "has worktree-agent-active && [ -d '$ROOT/wt-active' ]"
check "own never-pushed branch kept" "has mine"
check "main fast-forwarded" "[ \"\$(git rev-parse main)\" = \"\$(git rev-parse origin/main)\" ]"
check "output is JSON naming the removal" "printf '%s' \"\$out\" | node -e 'const m=JSON.parse(require(\"fs\").readFileSync(0,\"utf8\")).systemMessage;process.exit(/removed merged worktree/.test(m)&&/worktree-agent-done/.test(m)?0:1)'"

# A session started inside a merged worktree keeps its own checkout.
merged_gone self && wt self && g reset -q --hard "$base"
(cd "$ROOT/wt-self" && bash "$SCRIPT" >/dev/null)
check "own worktree kept when run inside it" "[ -d '$ROOT/wt-self' ] && listed self"
check "main worktree kept when run inside another" "[ -f '$ROOT/main/.gitignore' ]"
[ $fail -eq 0 ] && echo PASS || { echo "--- hook output:"; echo "$out"; exit 1; }
