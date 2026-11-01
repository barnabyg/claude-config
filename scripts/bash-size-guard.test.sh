#!/usr/bin/env bash
# Scenario test for ~/.claude/scripts/bash-size-guard.sh, fed the JSON payloads
# a PreToolUse hook receives.
set -u
DIR=${DIR:-$HOME/.claude/scripts}
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bash-size-guard-test.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

# payload <count> <text> [padding]: a command of <text> repeated <count> times,
# plus an optional extra field of that many bytes to inflate the payload alone.
payload() {
  node -e '
    const [count, text, padding = 0] = process.argv.slice(1);
    console.log(JSON.stringify({
      tool_name: "Bash",
      tool_input: { command: text.repeat(+count), description: "x".repeat(+padding) },
    }));
  ' "$@"
}
# run <payload-file>: sets $code and $err from running the guard on it.
run() {
  bash "$DIR/bash-size-guard.sh" <"$1" >"$ROOT/out" 2>"$ROOT/err"
  code=$?
  err=$(cat "$ROOT/err")
}

payload 1 ls >"$ROOT/p"
run "$ROOT/p"
check "a short command passes" '[ "$code" = 0 ] && [ -z "$err" ]'

payload 7000 x >"$ROOT/p"
run "$ROOT/p"
check "a command at the limit passes" '[ "$code" = 0 ] && [ -z "$err" ]'

payload 7001 x >"$ROOT/p"
run "$ROOT/p"
check "a command over the limit is blocked" '[ "$code" = 2 ]'
check "the block states the size and what to do" '[[ "$err" == *"7001 bytes"* && "$err" == *"Write tool"* ]]'

payload 3501 é >"$ROOT/p"
run "$ROOT/p"
check "multibyte text is measured in bytes, not characters" '[ "$code" = 2 ] && [[ "$err" == *"7002 bytes"* ]]'

payload 1 ls 9000 >"$ROOT/p"
run "$ROOT/p"
check "a large payload with a short command passes" '[ "$code" = 0 ] && [ -z "$err" ]'

node -e 'console.log("{".repeat(9000))' >"$ROOT/p"
run "$ROOT/p"
check "a malformed payload passes" '[ "$code" = 0 ]'

node -e 'console.log(JSON.stringify({tool_name: "Bash", tool_input: {}, pad: "x".repeat(9000)}))' >"$ROOT/p"
run "$ROOT/p"
check "a payload with no command passes" '[ "$code" = 0 ]'

exit "$fail"
