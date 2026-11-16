#!/usr/bin/env bash
# Scenario test for ~/.claude/scripts/run-exclusive.ps1. Uses a private mutex name
# so it neither waits for nor blocks real heavy runs on the machine.
set -u
DIR=${DIR:-$HOME/.claude/scripts}
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/run-exclusive-test.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
export CLAUDE_EXCLUSIVE_NAME="Local\\run-exclusive-test-$$"
unset CLAUDE_EXCLUSIVE_HELD CLAUDE_EXCLUSIVE_DISABLE
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
wrap() { pwsh -NoProfile -File "$DIR/run-exclusive.ps1" "$@"; }

wrap bash -c 'exit 3'
check "the command's exit code is passed through" '[ $? = 3 ]'

wrap no-such-command-xyz 2>"$ROOT/err"
code=$?
check "an unknown command exits 127" '[ "$code" = 127 ] && grep -q "not found" "$ROOT/err"'

wrap 2>/dev/null
check "no command is a usage error" '[ $? = 2 ]'

out=$(wrap bash -c 'printf "%s|" "$@"' x -t -TimeoutSec 5 -- -n)
check "switches after the command reach the command" '[ "$out" = "-t|-TimeoutSec|5|--|-n|" ]'

out=$(wrap pwsh -NoProfile -Command '(Get-Process -Id $PID).PriorityClass')
check "the command runs at BelowNormal priority" '[[ "$out" == BelowNormal* ]]'

# Two runs started together must not overlap: each logs start and end times.
job='echo "$1 start $(date +%s%N)" >>"$2"; sleep 2; echo "$1 end $(date +%s%N)" >>"$2"'
wrap bash -c "$job" _ A "$ROOT/log" 2>"$ROOT/errA" &
sleep 0.5
wrap bash -c "$job" _ B "$ROOT/log" 2>"$ROOT/errB" &
wait
first_end=$(awk '$2=="end"{print $3; exit}' "$ROOT/log")
second_start=$(awk '$2=="start"{n++; if(n==2){print $3; exit}}' "$ROOT/log")
check "concurrent runs are serialised" '[ -n "$first_end" ] && [ -n "$second_start" ] && [ "$second_start" -ge "$first_end" ]'
check "the queued run says it is waiting" 'grep -q "waiting" "$ROOT/errB" && grep -q "lock acquired" "$ROOT/errB"'

# The timeout counts from lock acquisition, not from the start of queueing.
wrap bash -c 'sleep 3' &
sleep 0.5
start=$(date +%s)
wrap -TimeoutSec 2 bash -c 'sleep 1; echo done' >"$ROOT/out" 2>/dev/null
code=$?
wait
check "queue time does not count against the timeout" '[ "$code" = 0 ] && grep -q done "$ROOT/out"'

start=$(date +%s)
wrap -TimeoutSec 1 bash -c 'sleep 30 & sleep 30; wait' 2>"$ROOT/err"
code=$?
elapsed=$(( $(date +%s) - start ))
check "a run over its timeout exits 124 promptly" '[ "$code" = 124 ] && [ "$elapsed" -lt 15 ]'

timeout 20 pwsh -NoProfile -File "$DIR/run-exclusive.ps1" pwsh -NoProfile -File "$DIR/run-exclusive.ps1" bash -c 'exit 0'
check "a nested call does not deadlock" '[ $? = 0 ]'

# The lock is released after a run, including a failing one.
timeout 20 pwsh -NoProfile -File "$DIR/run-exclusive.ps1" bash -c 'exit 0'
check "the lock is free again afterwards" '[ $? = 0 ]'

exit "$fail"
