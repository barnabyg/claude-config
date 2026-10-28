#!/usr/bin/env bash
# Scenario test for ~/.claude/scripts/hygiene-trigger.sh and hygiene-run.sh,
# with gh and claude replaced by stubs and a throwaway repo as the project.
set -u
DIR=${DIR:-$HOME/.claude/scripts}
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hygiene-test.XXXXXX")
ROOT=$(cygpath -m "$ROOT" 2>/dev/null || echo "$ROOT") # match git's paths
trap 'rm -rf "$ROOT"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
g() { git -c core.autocrlf=false -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

# Stubs. gh answers from files in $STUB and logs every call; claude records how
# it was started, then waits so the test can see the trigger return first.
STUB="$ROOT/stub" && mkdir -p "$STUB/bin"
cat >"$STUB/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$STUB/calls"
case "$*" in
*"--state all"*) cat "$STUB/reviews" 2>/dev/null || true ;;
*"--state closed"*) cat "$STUB/count" ;;
*"--state open"*) cat "$STUB/first" 2>/dev/null || echo 7 ;;
"issue create"*) echo "https://github.com/o/r/issues/7" ;;
esac
SH
cat >"$STUB/bin/claude" <<'SH'
#!/usr/bin/env bash
{ echo "args=$*"; echo "cwd=$(pwd -W)"; echo "run=${HYGIENE_RUN:-}"; echo "nested=${CLAUDECODE:-unset}"
  echo "noconv=${MSYS_NO_PATHCONV:-}"; ls; } >"$STUB/claude"
sleep 3
[ -f "$STUB/claude-fails" ] && { echo '{"is_error":true}'; exit 1; }
echo '{"type":"result","is_error":false}'
SH
chmod +x "$STUB/bin/"*
export STUB PATH="$(cygpath -u "$STUB/bin" 2>/dev/null || echo "$STUB/bin"):$PATH" CLAUDECODE=1 # C:/ would split PATH

cd "$ROOT"
g init -q --bare origin.git
g clone -q origin.git main 2>/dev/null
cd main
echo base >file.txt && g add file.txt && g commit -qm init && g push -q origin main
g remote set-head origin main
echo uncommitted >>file.txt # the user's work in progress

reset() { rm -f "$STUB"/{calls,reviews,count,first,claude,claude-fails}; echo "${1:-5}" >"$STUB/count"; }
called() { grep -q -- "$1" "$STUB/calls" 2>/dev/null; }
# Waits for the detached worker, which closes the review issue when it ends.
wait_worker() { for _ in $(seq 100); do grep -q "issue close 7" "$STUB/calls" 2>/dev/null && return; sleep 0.2; done; }
run() { out=$(bash "$DIR/hygiene-trigger.sh"); }

reset && run
check "no config: nothing queried" "! [ -f '$STUB/calls' ] && [ -z \"\$out\" ]"

mkdir -p .claude && echo '{"testCommand": "echo ran-tests; ls >tests-saw.txt"}' >.claude/hygiene.json
reset 4 && run
check "below threshold: no review" "! called 'issue create' && [ -z \"\$out\" ]"
check "first cycle counts every completed ticket" "called '--search reason:completed -label:hygiene -label:hygiene-run'"

reset && run
check "trigger returns before the review ends" "! called 'issue close 7'"
check "threshold reached: review issue created" "called 'issue create --label hygiene-run'"
check "labels ensured" "called 'label create hygiene ' && called 'label create hygiene-run'"
check "user told" "printf '%s' \"\$out\" | node -e 'process.exit(/#7 started/.test(JSON.parse(require(\"fs\").readFileSync(0,\"utf8\")).systemMessage)?0:1)'"
wait_worker
check "claude runs the skill with the review and test log" "grep -q 'args=-p /hygiene 7 .*tests-7.log' '$STUB/claude'"
check "claude runs read-only" "grep -q 'dontAsk' '$STUB/claude' && grep -q 'disallowedTools Edit Write' '$STUB/claude'"
check "claude marked as the review and not nested" "grep -qx 'run=1' '$STUB/claude' && grep -qx 'nested=unset' '$STUB/claude'"
check "slash command shielded from MSYS path rewriting" "grep -qx 'noconv=1' '$STUB/claude'"
check "claude runs in a separate worktree" "! grep -qx 'cwd=$ROOT/main' '$STUB/claude' && grep -qx 'file.txt' '$STUB/claude'"
logs=$(git rev-parse --path-format=absolute --git-common-dir)/hygiene
check "tests ran in the worktree, timed" "grep -q ran-tests '$logs/tests-7.log' && grep -q '^# exit 0 after' '$logs/tests-7.log'"
check "review closed as completed" "called 'issue close 7 --reason completed'"
check "worktree removed, user's work untouched" "[ \$(git worktree list | wc -l) -eq 1 ] && grep -q uncommitted file.txt && ! [ -f tests-saw.txt ]"

# Fixtures mirror the trigger's --jq output; real gh gives an open issue an empty stateReason.
reset && printf '3|OPEN||%s\n' "$(date -u +%FT%TZ)" >"$STUB/reviews" && run
check "running review: nothing else happens" "! called '--state closed' && ! called 'issue create'"

reset 0 && printf '3|OPEN||2020-01-01T00:00:00Z\n' >"$STUB/reviews" && run
check "stale review closed as not planned" "called 'issue close 3 --reason not planned'"

reset 0 && printf '4|CLOSED|COMPLETED|2026-05-01T00:00:00Z\n5|CLOSED|NOT_PLANNED|2026-06-01T00:00:00Z\n' >"$STUB/reviews" && run
check "counts from the last completed review" "called '--search closed:>2026-05-01T00:00:00Z reason:completed'"

reset && echo 6 >"$STUB/first" && run
check "lost race: own review closed as duplicate, no worker" "called 'issue close 7 --reason not planned --comment Duplicate of #6' && [ -z \"\$out\" ]"

reset && HYGIENE_RUN=1 bash "$DIR/hygiene-trigger.sh"
check "the review's own session triggers nothing" "! [ -f '$STUB/calls' ]"

reset && touch "$STUB/claude-fails" && run && wait_worker
check "failed review reported and closed as not planned" "called 'issue comment 7 --body Hygiene review failed' && called 'issue close 7 --reason not planned'"

[ $fail -eq 0 ] && echo PASS || exit 1
