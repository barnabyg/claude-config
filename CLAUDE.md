# Global CLAUDE.md

## Working style

- Be direct. No filler, unnecessary preambles, or reflexive praise.
- Say clearly when something is wrong or poorly designed. Explain important trade-offs concisely.
- Prefer pragmatic solutions over theoretical perfection. Use metric units.
- Minimize intermediate commentary. Do not narrate routine actions, searches, file reads, edits, or test runs. Give updates only for significant findings, blockers, important decisions, or changes to the plan.

## Defaults (unless project CLAUDE.md overrides)

- Check for existing tests and run the relevant focused tests after code changes. Follow the verification policy below for when a full suite is required; do not run a full suite merely because a generic skill says to.
- Lint before committing.
- Update relevant documentation when changing public interfaces.
- Use conventional commit messages: `type(scope): description`.
- When choosing a language for a new project, prefer TypeScript with strict mode; respect an existing project's language and conventions.

## Conditional guidance (read when the trigger applies)

- **Verification:** Before creating or changing executable code, read `~/.claude/agent-guidance/verification.md`. It defines the canonical verification command, required gates, zero-warning standard, and exceptions.
- **Investigation:** Before substantive optimisation, debugging, or performance-regression changes, read `~/.claude/agent-guidance/investigation.md` for baselines, attempt logging, and stopping rules.
- **Images on GitHub:** To show a screenshot or other image in a PR, issue or comment, use the `pr-screenshots` skill. `gh` can't attach images, but that skill can embed them.

## Commits and publishing

When a task includes commits:

- At the start of a new project, initialise a Git repository if one does not exist. Use feature branches for distinct functionality.
- Commit after each logical unit of work, rather than making one large final commit. Create one commit per implementation ticket or code-review finding. Keep unrelated work separate and stage selectively when work overlaps.
- Each commit must pass its focused tests. Before pushing a PR branch, run **only the fast checks**: formatting, lint, type checking, and the tests affected by the change. This overrides skill instructions to run the full test suite, such as in `implement`. GitHub CI is the full verification, and work isn't finished until CI is green on the pushed commit.
- Run full verification locally before pushing **only** when the repo has no CI, CI doesn't cover every required gate (for example Windows-only behaviour or end-to-end tests), or the push goes directly to the default branch. A passing full verification may satisfy both handoff and pre-push requirements when the verified tree is identical to the tree being pushed.
- Ask before combining technically inseparable tickets or findings.
- Preserve commit history: squash only when explicitly requested; force-push or otherwise rewrite pushed history only with explicit approval.

State which branch was pushed. Describe work as shipped or available from a normal clone only when the remote default branch contains it. When normal-clone availability matters, confirm the default branch and verify a clean checkout. Verify installation, startup, packaging, and deployment changes from a clean checkout when practical; ignored, untracked, or generated local files are not evidence.

## CI test behaviour

- Configure CI test runners to stop on the first failure, avoiding wasted CI time after a run has already failed. Keep local test runs able to report all failures.
- When creating or changing test configuration, use a CI-scoped setting: for Playwright, `maxFailures: process.env.CI ? 1 : 0`; for Vitest or Jest, use their equivalent CI-only `bail` setting. Do not indiscriminately impose fail-fast on local runs.

## Long-running commands

- Background jobs only notify on exit, so a hang can be silent. Give every `run_in_background` command a hard wall-clock limit (roughly three times the expected duration). For a Unix-like shell, an example is `CI=1 timeout 900 npm test </dev/null >log 2>&1`. On native Windows PowerShell, use an appropriate Windows-compatible timeout/process-control mechanism rather than assuming Unix `timeout` exists.
- Capture logs; avoid watch/interactive modes. Treat hitting the timeout as a possible hang and investigate before rerunning. Ensure timed-out commands do not leave task-owned child processes running. For development servers, use `preview_start` where available.

## Parallel agents and Git worktrees

- Give each concurrent write-capable agent or task its own branch-backed worktree, created from an explicit base ref. Read-only agents may share a checkout. Keep all edits, builds, tests, and Git operations inside the assigned worktree.
- Worktrees isolate files, not host resources. Namespace collision-prone ports, databases, temporary paths, build outputs, and container/Compose resources per worktree; serialize commands when safe isolation is unavailable.
- Integrate completed branches in one designated worktree. Apply the verification policy above; integration does **not** independently require a redundant full local suite when CI provides the required coverage. Never modify or remove another agent's active worktree.
- If worktrees are unavailable, keep parallel agents read-only and serialize stateful work.

## Post-merge cleanup

Cleanup is part of completing PR work. When you merge a PR, or learn during an active or resumed task that its PR has merged, perform cleanup before the final handoff without waiting for a separate tidy-up request.

- Confirm the PR's merged state and target branch through the hosting service. Inspect the task's worktrees and working directories for uncommitted, untracked, ignored, and unpushed work; preserve anything still needed before cleanup. A merged PR alone does not prove that all local work is preserved.
- Stop task-owned background processes and release task-owned temporary resources. Keep shared resources and directories used by active tasks intact.
- For tool-managed worktrees, use that tool's supported cleanup mechanism when available. Remove clean, manually managed worktrees with `git worktree remove`. Remove other task-created temporary working directories only after verifying their resolved paths and that they contain no needed work; use scoped removal rather than broad filesystem cleanup. Do not assume Codex's worktree archive command exists in Claude Code.
- Delete task-owned local branches only after verifying their work is integrated or otherwise preserved. Prefer normal safe branch deletion; if it refuses (for example, after a squash merge), retain the branch and report why. Remote branch deletion requires explicit authorisation or an established repository policy.
- Verify cleanup and report what was removed or archived and anything retained with its reason. If cleanup is blocked, include the concrete remaining action in the handoff; treat cleanup as complete only when every task-owned resource is removed, archived, or deliberately retained with an explained reason.

## Windows environment

- The host environment is Windows 11. Use PowerShell syntax for native Windows commands when Bash alternatives are unavailable.
- Commands given to the user to run manually must use PowerShell 7 (`pwsh`) in `powershell`-tagged code blocks. Use PowerShell constructs such as `foreach ($x in ...) { }` and `$env:VAR`; do not give the user Bash loops, heredocs, `export`, or Bash command substitution. Bash syntax is fine for agent-executed Bash commands.
- Prefer forward slashes in paths where cross-platform tools support them. Prefer LF line endings for code files; be alert to CRLF/LF differences.
- In native Windows PowerShell, use Node.js `.cmd` shims: `npm.cmd`, `npx.cmd`, `pnpm.cmd`, `yarn.cmd`, and repository-local launchers such as `.\node_modules\.bin\playwright.cmd`. Prefer repository scripts through `npm.cmd run <script>`. If a `.ps1` shim is blocked, switch to `.cmd`; preserve the execution policy.
- Git Bash keeps only about the first 8,186 bytes of a `bash -c` string (measured on 5.3.15). Bash tool commands over that fail with `unexpected EOF while looking for matching`, and the reported line is just the last apostrophe before the cut, so changing the quoting will not help. Keep inline commands under about 7 KB, and run anything longer from a script file. Outside the tool's `eval` wrapper, a plain long `bash -c` can stop at the cut and still exit 0, so never pass long scripts that way.

## GitHub authentication

- Use `gh` outside the sandbox where configured through Claude Code's `sandbox.excludedCommands` in `settings.json`. A sandboxed `gh auth status` failure is inconclusive because host-keyring credentials may be unavailable there. Do not start `gh auth login` on that evidence alone. If `gh` still fails with an authentication error outside the sandbox, report the failure rather than initiating a new login.
- Keep credentials in the host keyring. Full Access, persisted `GH_TOKEN`/`GITHUB_TOKEN`, and `gh auth login --insecure-storage` are not authentication workarounds.

## Compatibility and critical workflows

- Treat released backup, export, and persisted-data formats as compatibility contracts. Preserve readable old formats. Before making old data unreadable, obtain explicit approval, identify affected versions, and propose a migration.
- Test critical workflows spanning UI, API, and storage at the user-facing boundary; unit or API tests alone are insufficient.

## Implementation handoff

For behaviour changes, report:

- a clear, concise summary of significant user-visible and technical changes;
- concrete manual tests, expected results, and any prerequisites, commands, URLs, flags, or test data;
- automated checks and their results; and
- important untested, uncertain, or out-of-scope behaviour.

## Manual testing

- Every ticket requiring manual verification must provide **one documented command** that prepares and launches the application in a testable state, including which directory to run it from.
- Supply the expected behaviour and a short, specific test scenario. Manual verification must not require knowledge of the application's internal tooling.
- Focus manual testing on changed behaviour and regression risks rather than repeating automated commands. If meaningful manual testing does not apply, say so.
