#!/usr/bin/env bash
# Starts a report-only hygiene review (the /hygiene skill) once enough tickets
# have closed since the last one; run by a Claude Code SessionStart hook.
# Projects opt in by committing .claude/hygiene.json. The cycle's state lives
# in GitHub, not on disk, so worktrees, parallel sessions and other machines
# agree on it: each review is an issue labelled hygiene-run, open while the
# review runs and closed as completed when it finishes. Tickets count when
# closed as completed after the last completed review was opened, excluding
# hygiene and hygiene-run issues. An open review older than 6 hours is taken as
# crashed and closed as not planned. The review runs detached in hygiene-run.sh.
set -u
[ -z "${HYGIENE_RUN:-}" ] || exit 0 # the review's own session
top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
config="$top/.claude/hygiene.json"
[ -f "$config" ] || exit 0
gh() { timeout 15 gh "$@"; } # timeout runs the real gh, not this function

mapfile -t cfg < <(node -e '
  const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  console.log(c.threshold ?? 5); console.log(c.maxBudgetUsd ?? 5); console.log(c.testCommand ?? "");
' "$config" 2>/dev/null) || exit 0
threshold=${cfg[0]:-5} budget=${cfg[1]:-5} test_cmd=${cfg[2]:-}

reviews=$(gh issue list --label hygiene-run --state all --limit 20 \
  --json number,state,stateReason,createdAt \
  --jq '.[] | "\(.number)|\(.state)|\(.stateReason)|\(.createdAt)"' 2>/dev/null) || exit 0
# "|" rather than tabs: read collapses adjacent tabs, and an open issue's
# stateReason is empty, which would shift the fields.
stale_before=$(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%SZ)
since=''
while IFS='|' read -r number state reason created; do
  [ -n "$number" ] || continue
  if [ "$state" = OPEN ]; then
    [[ "$created" < "$stale_before" ]] || exit 0 # a review is running
    gh issue close "$number" --reason "not planned" \
      --comment "Closed by the hygiene trigger: still open after 6 hours, so the review is taken as crashed." >/dev/null 2>&1
  elif [ "$reason" = COMPLETED ] && [[ "$created" > "$since" ]]; then
    since=$created
  fi
done <<<"$reviews"

query='reason:completed -label:hygiene -label:hygiene-run'
[ -n "$since" ] && query="closed:>$since $query"
count=$(gh issue list --state closed --search "$query" --limit "$threshold" \
  --json number --jq length 2>/dev/null) || exit 0
[ "$count" -ge "$threshold" ] || exit 0

gh label create hygiene --color c5def5 --force \
  --description "Found by a hygiene review" >/dev/null 2>&1
gh label create hygiene-run --color ededed --force \
  --description "Tracks one hygiene review; open while it runs" >/dev/null 2>&1
url=$(gh issue create --label hygiene-run --title "Hygiene review $(date -u +%F)" \
  --body "Automatic report-only review after $count tickets closed${since:+ since $since}. Findings are filed as issues labelled \`hygiene\`; the summary follows as a comment." 2>/dev/null) || exit 0
review=${url##*/}

# Two sessions starting together can both get here; the lowest number wins.
first=$(gh issue list --label hygiene-run --state open --json number --jq 'map(.number) | min' 2>/dev/null)
if [ -n "$first" ] && [ "$first" != null ] && [ "$first" != "$review" ]; then
  gh issue close "$review" --reason "not planned" --comment "Duplicate of #$first." >/dev/null 2>&1
  exit 0
fi

nohup bash "$(dirname "$0")/hygiene-run.sh" "$top" "$review" "$budget" "$test_cmd" \
  </dev/null >/dev/null 2>&1 &
disown

msg="Hygiene review #$review started in the background for $(basename "$top") ($count tickets closed since the last one). It files issues labelled hygiene and changes no code."
printf '{"systemMessage":"%s"}\n' "$msg"
