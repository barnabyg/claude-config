# Global CLAUDE.md

## Working Style

- Be direct. No filler, no "great question", no unnecessary preamble.
- When something is wrong or poorly designed, say so clearly.
- Explain trade-offs concisely when making decisions.
- Prefer pragmatic solutions over theoretically perfect ones.
- Use metric units.
- Minimize intermediate commentary. Don't narrate routine actions, searches, file reads, edits, or test runs. Give intermediate updates only for significant findings, blockers, important decisions, or changes to the plan.

## Defaults (Unless Project CLAUDE.md Overrides)

- Always check for and run existing tests after code changes.
- Always lint before committing.
- Always update relevant documentation when changing public interfaces.
- Write conventional commit messages: `type(scope): description`.
- Prefer TypeScript. Use strict mode.

## Conditional Guidance (read when the trigger applies)

- **Verification:** Before creating or changing executable code, read `~/.claude/agent-guidance/verification.md`. It defines the canonical verification command, required gates, zero-warning standard, and exceptions.
- **Investigation:** Before substantive optimisation, debugging, or performance-regression changes, read `~/.claude/agent-guidance/investigation.md` for baselines, attempt logging, and stopping rules.
- **Images on GitHub:** To show a screenshot or other image in a PR, issue or comment, use the `pr-screenshots` skill. `gh` can't attach images, but that skill can embed them.

## Compatibility and Critical Workflows

- Treat released backup, export, and persisted-data formats as compatibility contracts. Preserve readable old formats. Before making old data unreadable, get explicit approval, identify affected versions, and propose a migration.
- Test critical workflows spanning UI, API, and storage at the user-facing boundary; unit or API tests alone are insufficient.

## Long-Running Commands

Background jobs only notify on exit, so a hang is silent. Give every `run_in_background` command a hard limit (~3x expected): `CI=1 timeout 900 npm test </dev/null >log 2>&1`. No watch mode. Treat hitting the limit as a hang and find the cause before rerunning. Dev servers: use `preview_start`.

## GitHub CI

Make CI test runs stop at their first failure. When creating or changing test config, set `maxFailures: 1` for CI, scoped so local runs still report every failure: `maxFailures: process.env.CI ? 1 : 0` in Playwright. Other runners use their equivalent, such as `bail: 1` in Vitest and Jest.

## Windows Environment

- This is a Windows 11 system.
- Use PowerShell syntax for system commands when bash alternatives aren't available.
- Commands you give me to run myself must be PowerShell 7 (`pwsh`), in `powershell`-tagged code blocks: `foreach ($x in ...) { }`, `$env:VAR`, and `.cmd` shims; `&&`/`||` chaining is fine. Bash syntax is only for your own Bash tool calls; never hand me a bash loop, heredoc, `export`, or `$(...)`-style bash expansion.
- Use forward slashes in paths where possible for cross-platform compatibility.
- Be aware of CRLF vs LF line endings — prefer LF for code files.
- In PowerShell, use Node.js `.cmd` shims: `npm.cmd`, `npx.cmd`, `pnpm.cmd`, `yarn.cmd`, and repo-local launchers such as `.\node_modules\.bin\playwright.cmd`. Prefer repository scripts via `npm.cmd run <script>`. If a `.ps1` shim is blocked, switch to `.cmd`; don't change the execution policy.

## GitHub Authentication

- `gh` runs outside the sandbox via `sandbox.excludedCommands` in settings.json. If it still fails with an auth error, don't run `gh auth login` — report the failure.
- Keep credentials in the host keyring. Persisted `GH_TOKEN`/`GITHUB_TOKEN` and `gh auth login --insecure-storage` are not acceptable workarounds.

## Git Usage

- Always initialize a git repo (`git init`) at project start if one doesn't already exist.
- Make small, frequent commits with clear conventional commit messages.
- Commit after completing each logical unit of work — don't batch everything into one giant commit at the end.
- Create one commit per implementation ticket or code-review finding. Keep unrelated work separate and stage selectively when work overlaps. Ask before combining technically inseparable tickets or findings.
- Each commit must pass its focused tests. Run full verification before pushing the series. One passing full verification can cover both handoff and pre-push when the verified tree is identical to the pushed tree.
- Use feature branches for distinct pieces of functionality.
- Preserve commit history: squash only when explicitly requested.
- Never force push or otherwise rewrite pushed history.

### Publishing

- State which branch was pushed.
- Describe work as shipped or available from a normal clone only when the remote default branch contains it. When that matters, confirm the default branch and verify a clean checkout.
- Verify installation, startup, packaging, and deployment changes from a clean checkout when practical; ignored, untracked, or generated local files are not evidence.

### Parallel Agents and Worktrees

- Give each concurrent write-capable agent its own branch-backed worktree created from an explicit base ref. Read-only agents may share a checkout. Keep all edits, builds, tests, and Git operations inside the assigned worktree.
- Worktrees isolate files, not host resources. Namespace collision-prone ports, databases, temp paths, build outputs, and container/Compose resources per worktree; serialize commands when safe isolation isn't available.
- Integrate completed branches and run full verification in one designated worktree. Never modify or remove another agent's active worktree; remove clean, preserved worktrees with `git worktree remove`.
- If worktrees are unavailable, keep parallel agents read-only and serialize stateful work.

## Implementation Handoff

For behavior changes, report:

- A clear and concise summary of significant user-visible and technical changes. Minimise jargon;
- Concrete manual tests, their expected results, and any prerequisites, commands, URLs, flags, or test data;

## Manual Testing

Every ticket requiring manual verification must provide a single documented command that prepares and launches the application in a testable state. Ensure the user knows which folder they should be in when they run the command. The agent should supply the expected behaviour and a short, specific test scenario. Manual verification must not require knowledge of the application's internal tooling.
Focus manual testing on changed behavior and regression risks rather than repeating automated commands. If meaningful manual testing doesn't apply, say so.
