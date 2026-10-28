#!/usr/bin/env bash
# Scenario test for ~/.claude/scripts/pr-asset.sh against a fake gh that
# answers its GitHub API calls and logs them with their request bodies.
set -u
SCRIPT=${SCRIPT:-$HOME/.claude/scripts/pr-asset.sh}
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/pr-asset-test.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

export STATE="$ROOT/state"
mkdir -p "$ROOT/bin" "$STATE"
cat >"$ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
# The ref lives in $STATE/head; $STATE/races makes that many ref updates
# fail as non-fast-forward after another writer moves the head.
input=''
for ((i = 1; i <= $#; i++)); do [ "${!i}" = --input ] && { j=$((i + 1)); input=${!j}; }; done
echo "$* ${input:+$(cat "$input")}" >>"$STATE/calls"
next() { n=$(($(cat "$STATE/n" 2>/dev/null || echo 0) + 1)); echo $n >"$STATE/n"; echo "$1$n"; }
case "$*" in
  "repo view"*) echo o/r ;;
  "api repos/o/r/git/ref/heads/pr-assets"*) cat "$STATE/head" 2>/dev/null || exit 1 ;;
  "api repos/o/r/git/commits/"*) echo "tree-of-$(cat "$STATE/head")" ;;
  *"POST repos/o/r/git/blobs"*) next blob ;;
  *"POST repos/o/r/git/trees"*) next tree ;;
  *"POST repos/o/r/git/commits"*) next commit | tee "$STATE/last" ;;
  *"POST repos/o/r/git/refs"*) cp "$STATE/last" "$STATE/head" ;;
  *"PATCH repos/o/r/git/refs/heads/pr-assets"*)
    races=$(cat "$STATE/races" 2>/dev/null || echo 0)
    if [ "$races" -gt 0 ]; then
      echo $((races - 1)) >"$STATE/races"; next other >"$STATE/head"; exit 1
    fi
    cp "$STATE/last" "$STATE/head" ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$ROOT/bin/gh"
export PATH="$ROOT/bin:$PATH"
reset() { rm -f "$STATE"/*; }

cd "$ROOT"
git -c init.defaultBranch=main init -q repo && cd repo && git switch -qc feat/login
printf 'png-bytes' >"Login page.png"
printf 'gif-bytes' >flow.gif

# First upload: no branch yet, so an orphan commit and a new ref.
reset
out=$(bash "$SCRIPT" "Login page.png" flow.gif)
check "first upload exits 0" '[ $? -eq 0 ]'
check "prints a pinned image line per file" '[ "$out" = "![Login-page](https://github.com/o/r/blob/commit4/feat-login/Login-page.png?raw=true)
![flow](https://github.com/o/r/blob/commit4/feat-login/flow.gif?raw=true)" ]'
check "uploads file content as base64" 'grep -q "\"content\":\"$(printf png-bytes | base64)\"" "$STATE/calls"'
check "orphan commit has no parents" 'grep -q "\"parents\":\[\]" "$STATE/calls"'
check "orphan tree has no base" '! grep -q base_tree "$STATE/calls"'
check "creates the ref" 'grep -q "POST repos/o/r/git/refs .*refs/heads/pr-assets" "$STATE/calls"'
check "ref points at the new commit" '[ "$(cat "$STATE/head")" = commit4 ]'

# Later upload: builds on the existing head and fast-forwards it.
reset; echo commit0 >"$STATE/head"
out=$(bash "$SCRIPT" -d pr-42 flow.gif)
check "-d sets the folder" '[ "$out" = "![flow](https://github.com/o/r/blob/commit3/pr-42/flow.gif?raw=true)" ]'
check "tree builds on the head tree" 'grep -q "\"base_tree\":\"tree-of-commit0\"" "$STATE/calls"'
check "commit's parent is the head" 'grep -q "\"parents\":\[\"commit0\"\]" "$STATE/calls"'
check "ref update is fast-forward only" 'grep -q "PATCH .*\"force\":false" "$STATE/calls"'

# Race: another writer moves the head once; the retry rebuilds on it.
reset; echo commit0 >"$STATE/head"; echo 1 >"$STATE/races"
out=$(bash "$SCRIPT" flow.gif)
check "race retries and succeeds" '[ $? -eq 0 ] && [ "$(cat "$STATE/head")" = commit6 ]'
check "retry builds on the moved head" 'grep -q "\"parents\":\[\"other4\"\]" "$STATE/calls"'
check "blobs are not re-uploaded on retry" '[ "$(grep -c git/blobs "$STATE/calls")" -eq 1 ]'

# Persistent race gives up rather than looping forever.
reset; echo commit0 >"$STATE/head"; echo 9 >"$STATE/races"
bash "$SCRIPT" flow.gif >/dev/null 2>&1
check "gives up after 3 lost races" '[ $? -eq 1 ] && [ "$(grep -c PATCH "$STATE/calls")" -eq 3 ]'

# Bad input fails before any API write.
reset
bash "$SCRIPT" missing.png >/dev/null 2>&1
check "missing file exits 1" '[ $? -eq 1 ] && ! grep -q POST "$STATE/calls"'
head -c $((10 * 1024 * 1024 + 1)) /dev/zero >big.png
bash "$SCRIPT" big.png >/dev/null 2>&1
check "file over 10 MB exits 1" '[ $? -eq 1 ] && ! grep -q POST "$STATE/calls"'
bash "$SCRIPT" >/dev/null 2>&1
check "no files exits 2" '[ $? -eq 2 ]'

exit $fail
