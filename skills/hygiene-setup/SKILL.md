---
name: hygiene-setup
description: Opt the current project into automatic hygiene reviews by writing and committing a validated .claude/hygiene.json.
disable-model-invocation: true
---

# Hygiene setup

Opts this project into the hygiene cycle: after every `threshold` tickets closed as completed, a session start launches a background `/hygiene` review that files findings as GitHub issues. The machinery is global (`~/.claude/scripts/hygiene-trigger.sh` and `hygiene-run.sh`); a project joins by committing `.claude/hygiene.json`. The keys and defaults are defined once, in the Configuration section of `~/.claude/skills/hygiene/SKILL.md`; read it first.

Run every step even when `.claude/hygiene.json` already exists: then this is a re-check, and the existing values are the starting proposal.

## Steps

1. **Check prerequisites.** Each one that fails stops setup with the fix stated:
   - The folder is a git repo whose `origin` is on GitHub, and `refs/remotes/origin/HEAD` is set (`git remote set-head origin --auto` fixes it).
   - `gh repo view --json hasIssuesEnabled,viewerPermission` shows issues enabled and `WRITE`, `MAINTAIN` or `ADMIN` permission.
   - The headless CLI can actually call the model: `env -u CLAUDECODE claude -p "Reply OK" --model haiku --max-budget-usd 0.05 </dev/null` prints OK. `claude auth status` is not enough, because it reports an expired login as logged in. On a 401 the user runs `claude`, then `/login`.
2. **Find the test command.** Work it out from the repo (package scripts, test-runner config, CI workflow, the verification command in `CLAUDE.md`/`AGENTS.md`). It runs under `bash -c` in a fresh worktree of the default branch with nothing installed, so it must: install dependencies from the lockfile, run the full suite non-interactively, and print a duration for every test (for example `npm ci && npx vitest run --reporter=verbose`, `uv sync && uv run pytest --durations=0 -q`). A repo with no tests gets no `testCommand`; say so.
3. **Prove the test command.** Run it exactly as the review will: `git fetch origin`, `git worktree add --detach <temp dir> origin/HEAD`, `bash -c "<command>"` inside it, then `git worktree remove --force <temp dir>`. Done when it exits 0 and its output shows per-test durations. On failure, fix the command and rerun; a suite that fails on the default branch is reported to the user, since the review would measure a broken suite.
4. **Decide the baseline.** Count the tickets the first review would see: `gh issue list --state closed --search "reason:completed -label:hygiene -label:hygiene-run" --limit 1000 --json number --jq length`, and check `gh issue list --label hygiene-run --state all` for earlier reviews. When there are no earlier reviews and the count is at least `threshold`, the first review fires on the next session start. Ask the user to choose:
   - **Review soon**: leave it; the next session start launches the first review.
   - **Count from now**: create a baseline review issue, so only tickets closed from now on count. Create the two labels with the `gh label create` lines from `hygiene-trigger.sh`, then `gh issue create --label hygiene-run --title "Hygiene baseline <date>" --body "Hygiene cycle enabled; tickets count from here."` and close it with `--reason completed`.
5. **Agree the config.** Propose values and ask the user to confirm or change them: `testCommand` from step 3, and `threshold`, `maxBudgetUsd`, `maxTickets`, `docLineBudget`, `slowTestMs`, with the default as the recommended option. A suite with a known slow tier (integration, browser) is a reason to suggest a higher `slowTestMs`; a large doc set, a higher `docLineBudget`.
6. **Write and commit.** Write `.claude/hygiene.json` with `testCommand` plus only the keys that differ from their defaults, two-space indented, LF line endings. Commit it by path on its own, following the project's branch and commit conventions, as `chore(hygiene): opt into hygiene reviews`.
7. **Report.** Tell the user: the final config, the baseline choice and what it means for when the first review runs (now, or after `threshold` more tickets), the measured test-command duration, and that the trigger reads the file from the working tree: new sessions in this checkout count from now, while other machines and clones join once the commit reaches the default branch.
