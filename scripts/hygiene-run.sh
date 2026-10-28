#!/usr/bin/env bash
# Runs one hygiene review for hygiene-trigger.sh, detached from the session
# that started it. Usage: hygiene-run.sh <repo> <review-issue> <budget-usd> [test-command]
# It reviews the remote default branch in a throwaway worktree, so the user's
# checkout and uncommitted work are never touched. The test command (if any)
# runs first and its log goes to the /hygiene skill, which runs headless with
# read-only tools plus the gh issue commands it needs to file findings. The
# review issue is closed as completed on success and as not planned with the
# reason on failure. Logs stay in <git-common-dir>/hygiene/.
set -u
top=$1 review=$2 budget=$3 test_cmd=${4:-}
cd "$top" || exit 1
dir="$(git rev-parse --path-format=absolute --git-common-dir)/hygiene"
mkdir -p "$dir"
exec >>"$dir/review-$review.log" 2>&1
echo "== $(date -u +%FT%TZ) review #$review of $top"

fail() {
  echo "FAILED: $1"
  gh issue comment "$review" --body "Hygiene review failed: $1. Log: \`$dir/review-$review.log\` on $(hostname)."
  gh issue close "$review" --reason "not planned"
  exit 1
}

git fetch --quiet origin || fail "git fetch failed"
default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || fail "origin/HEAD is not set"
wt="$(mktemp -d "${TMPDIR:-/tmp}/hygiene.XXXXXX")/repo"
trap 'git -C "$top" worktree remove --force "$wt"; rm -rf "$(dirname "$wt")"' EXIT
git worktree add --quiet --detach "$wt" "$default" || fail "could not create a worktree of $default"
cd "$wt" || fail "could not enter the worktree"

tests=''
if [ -n "$test_cmd" ]; then
  tests="$dir/tests-$review.log"
  start=$(date +%s)
  bash -c "$test_cmd" >"$tests" 2>&1
  echo "# exit $? after $(($(date +%s) - start))s" >>"$tests"
fi

# MSYS_NO_PATHCONV keeps Git Bash from rewriting "/hygiene" into a Windows path.
env -u CLAUDECODE HYGIENE_RUN=1 MSYS_NO_PATHCONV=1 claude -p "/hygiene $review $tests" \
  --permission-mode dontAsk \
  --allowedTools Read Grep Glob Agent \
  "Bash(gh issue list:*)" "Bash(gh issue view:*)" "Bash(gh issue create:*)" "Bash(gh issue comment:*)" \
  "Bash(git log:*)" "Bash(git show:*)" "Bash(git ls-files:*)" "Bash(wc:*)" \
  --disallowedTools Edit Write NotebookEdit \
  --max-budget-usd "$budget" --no-session-persistence --output-format json \
  </dev/null >"$dir/result-$review.json"
rc=$?
[ $rc -eq 0 ] && grep -q '"is_error":false' "$dir/result-$review.json" ||
  fail "claude exited with $rc; see result-$review.json"
gh issue close "$review" --reason completed
echo "== $(date -u +%FT%TZ) done"
