#!/usr/bin/env bash
# Uploads images to the pr-assets branch of the current repo's GitHub origin
# and prints one Markdown image line per file, pinned to the upload commit,
# for PR bodies, issues and comments. GitHub has no API for real attachments
# (drag-and-drop uploads need a browser session); this is the scriptable
# stand-in, used by the pr-screenshots skill.
# Usage: pr-asset.sh [-d folder] <file>...
# Files land at <folder>/<name>; the folder defaults to the current branch.
# The branch is created as an orphan on first use. Only the GitHub API is
# used, so the working tree, index and local branches are never touched.
# Pinning to the commit SHA keeps old links valid when a name is reused.
set -u
branch=pr-assets max_bytes=$((10 * 1024 * 1024))
folder=$(git branch --show-current 2>/dev/null)
if [ "${1:-}" = -d ]; then folder=${2:-}; shift 2; fi
[ $# -gt 0 ] || { echo "usage: pr-asset.sh [-d folder] <file>..." >&2; exit 2; }
# Paths go straight into JSON and URLs, so keep them to a safe alphabet.
clean() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }
folder=$(clean "${folder:-misc}")
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pr-asset.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
# api <method> <path> <jq> sends $tmp/body.json and prints the jq result.
api() { gh api -X "$1" "repos/$repo/$2" --input "$tmp/body.json" --jq "$3"; }

entries='' paths=()
for f in "$@"; do
  [ -f "$f" ] || { echo "not a file: $f" >&2; exit 1; }
  [ "$(wc -c <"$f")" -le "$max_bytes" ] || { echo "over 10 MB, shrink it first: $f" >&2; exit 1; }
  path="$folder/$(clean "$(basename "$f")")"
  { printf '{"encoding":"base64","content":"'; base64 <"$f" | tr -d '\r\n'; printf '"}'; } >"$tmp/body.json"
  blob=$(api POST git/blobs .sha) || exit 1
  entries+="${entries:+,}{\"path\":\"$path\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$blob\"}"
  paths+=("$path")
done

# Another agent may move the branch between reading and updating it; the ref
# update is fast-forward only, so rebuild on the new head and retry.
for _ in 1 2 3; do
  head=$(gh api "repos/$repo/git/ref/heads/$branch" --jq .object.sha 2>/dev/null) || head=''
  if [ -n "$head" ]; then
    base=$(gh api "repos/$repo/git/commits/$head" --jq .tree.sha) || exit 1
    printf '{"base_tree":"%s","tree":[%s]}' "$base" "$entries" >"$tmp/body.json"
    parents="[\"$head\"]"
  else
    printf '{"tree":[%s]}' "$entries" >"$tmp/body.json"
    parents='[]'
  fi
  tree=$(api POST git/trees .sha) || exit 1
  printf '{"message":"Add %s","tree":"%s","parents":%s}' "${paths[*]}" "$tree" "$parents" >"$tmp/body.json"
  commit=$(api POST git/commits .sha) || exit 1
  if [ -n "$head" ]; then
    printf '{"sha":"%s","force":false}' "$commit" >"$tmp/body.json"
    api PATCH "git/refs/heads/$branch" .object.sha >/dev/null || continue
  else
    printf '{"ref":"refs/heads/%s","sha":"%s"}' "$branch" "$commit" >"$tmp/body.json"
    api POST git/refs .object.sha >/dev/null || continue
  fi
  for path in "${paths[@]}"; do
    name=${path##*/}
    echo "![${name%.*}](https://github.com/$repo/blob/$commit/$path?raw=true)"
  done
  exit 0
done
echo "$branch kept moving under us; gave up after 3 attempts" >&2
exit 1
