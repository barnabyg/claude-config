#!/usr/bin/env bash
# Rejects Bash tool commands over 7000 bytes; run by a Claude Code PreToolUse
# hook. Git Bash keeps only about the first 8186 bytes of a bash -c string, and
# the Bash tool's wrapper adds to the command, so longer ones fail with a
# misleading "unexpected EOF while looking for matching" quoting error. Exit 2
# blocks the call and sends stderr to the agent. Anything unexpected lets the
# command through. Most calls end at the payload size check, without starting
# node, as JSON escaping means the command can't be longer than its payload.
set -u
LC_ALL=C # ${#input} counts bytes
limit=7000
input=$(cat)
[ "${#input}" -gt "$limit" ] || exit 0

size=$(printf '%s' "$input" | node -e '
  const payload = JSON.parse(require("fs").readFileSync(0, "utf8"));
  console.log(Buffer.byteLength(payload.tool_input?.command ?? ""));
' 2>/dev/null) || exit 0
[ "${size:-0}" -gt "$limit" ] || exit 0

cat >&2 <<EOF
Command not run: it is $size bytes, over the $limit-byte limit. Git Bash cuts longer commands off, which shows up as an "unexpected EOF" quoting error. Write the content to a file with the Write tool, or split the work into smaller commands, then run that.
EOF
exit 2
