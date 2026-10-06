#!/usr/bin/env bash
# Tidies a git checkout after its pull requests merge; run by a Claude Code
# SessionStart hook. It fetches with prune, moves a clean checkout off a merged
# branch onto the default branch, fast-forwards the default branch, and deletes
# local branches whose remote branch is gone and whose changes are already in
# the default branch. It also removes other worktrees on such branches, prunes
# records of worktrees whose folders are gone, and deletes never-pushed
# worktree-agent-* branches (left by Claude Code agent worktrees) whose changes
# are in the default branch. It works for squash merges too. It never deletes a
# branch with changes that are not in the default branch, never deletes any
# other never-pushed branch, and never touches a checkout or worktree with
# uncommitted or untracked changes, or a locked worktree.
set -u
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git remote get-url origin >/dev/null 2>&1 || exit 0
timeout 20 git fetch --prune --quiet origin 2>/dev/null || exit 0
git remote set-head origin --auto >/dev/null 2>&1
default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || exit 0
default=${default#origin/}
upstream_tree=$(git rev-parse "origin/$default^{tree}") || exit 0
done_list=()

# True when merging the branch into origin/<default> would change nothing.
merged() {
  local tree
  tree=$(git merge-tree --write-tree "origin/$default" "$1" 2>/dev/null | head -n 1) || return 1
  [ "$tree" = "$upstream_tree" ]
}

current=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
clean=$([ -z "$(git status --porcelain --untracked-files=no)" ] && echo yes)
gone=$(git for-each-ref --format='%(refname:short)	%(upstream:track)' refs/heads |
  awk -F'\t' '$2 == "[gone]" { print $1 }')

if [ -n "$current" ] && [ "$current" != "$default" ] && [ "$clean" = yes ] &&
  printf '%s\n' "$gone" | grep -qxF "$current" && merged "$current"; then
  if git switch --quiet "$default" 2>/dev/null; then
    done_list+=("left merged branch $current for $default")
    current=$default
  fi
fi

# Fast-forward the default branch only; never merge or rewrite it.
if git show-ref --verify --quiet "refs/heads/$default" &&
  git merge-base --is-ancestor "$default" "origin/$default" &&
  [ "$(git rev-parse "$default")" != "$(git rev-parse "origin/$default")" ]; then
  if [ "$current" = "$default" ]; then
    [ "$clean" = yes ] && git merge --ff-only --quiet "origin/$default" 2>/dev/null &&
      done_list+=("fast-forwarded $default")
  else
    git fetch --quiet . "origin/$default:$default" 2>/dev/null &&
      done_list+=("fast-forwarded $default")
  fi
fi

# Remove other worktrees whose branch is merged and gone from the remote. A
# plain remove ignores ignored files such as node_modules but refuses anything
# with uncommitted or untracked changes, so status is only checked first to
# avoid noise. The first entry is the main worktree and is never removed.
top=$(git rev-parse --show-toplevel)
remove_worktree() {
  [ -n "$wt_path" ] && [ "$wt_first" = no ] && [ "$wt_path" != "$top" ] || return 0
  [ -n "$wt_branch" ] && [ -z "$wt_locked" ] && [ -d "$wt_path" ] || return 0
  printf '%s\n' "$gone" | grep -qxF "$wt_branch" && merged "$wt_branch" || return 0
  [ -z "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ] || return 0
  git worktree remove "$wt_path" 2>/dev/null &&
    done_list+=("removed merged worktree $wt_path ($wt_branch)")
}
wt_path='' wt_first=yes
while IFS= read -r line; do
  case $line in
  "worktree "*) wt_path=${line#worktree } wt_branch='' wt_locked='' ;;
  "branch refs/heads/"*) wt_branch=${line#branch refs/heads/} ;;
  locked*) wt_locked=yes ;;
  '')
    remove_worktree
    [ -n "$wt_path" ] && wt_first=no
    wt_path=''
    ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null; echo)
[ -n "$(git worktree prune --verbose 2>&1)" ] && done_list+=("pruned records of missing worktrees")

# Agent worktree branches are never pushed, so they are never "gone"; they
# qualify by name instead. A branch still checked out anywhere is refused by
# git branch -D, which keeps an active agent's branch safe.
agent=$(git for-each-ref --format='%(refname:short)	%(upstream)' 'refs/heads/worktree-agent-*' |
  awk -F'\t' '$2 == "" { print $1 }')
gone=$(printf '%s\n%s' "$gone" "$agent")

while IFS= read -r branch; do
  [ -n "$branch" ] && [ "$branch" != "$current" ] && [ "$branch" != "$default" ] || continue
  if merged "$branch"; then
    tip=$(git rev-parse --short "$branch")
    # -D because a squash-merged branch is not an ancestor; merged() checked its content.
    git branch -D --quiet "$branch" 2>/dev/null && done_list+=("deleted merged branch $branch (was $tip)")
  fi
done <<<"$gone"

[ ${#done_list[@]} -eq 0 ] && exit 0
summary="git tidy in $(basename "$(git rev-parse --show-toplevel)"): $(IFS=';'; echo "${done_list[*]}" | sed 's/;/; /g')"
escaped=$(printf '%s' "$summary" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped" "$escaped"
