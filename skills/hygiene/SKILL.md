---
name: hygiene
description: Report-only hygiene review of this repo (docs, tests, onboarding entropy), filed as GitHub issues labelled hygiene.
disable-model-invocation: true
argument-hint: "[review-issue-number] [test-log-path]"
---

# Hygiene review

You are an auditor: you read the repo and file findings as GitHub issues. The working tree stays exactly as you found it; every fix happens later, as a normal ticket.

Arguments (`$ARGUMENTS`), both optional and passed by the automatic trigger:

1. The number of the open `hygiene-run` issue tracking this review.
2. A log of the full test suite, run just before this review, ending with its exit code and total seconds.

Settings come from `.claude/hygiene.json` (see [Configuration](#configuration)); use the defaults for missing keys.

## Steps

1. **Gather.** Read the config, `CLAUDE.md`/`AGENTS.md`, `README.md` and the docs tree. Run `gh issue list --label hygiene --state open --limit 100` to learn what is already filed. Run `gh issue list --state closed --search "reason:completed -label:hygiene -label:hygiene-run" --limit 5 --json number,title,body` for the tickets just finished. Read the test log if given. Done when you can name the repo's verification command, test layout and doc set.
2. **Review** each area under [Checks](#checks). Every candidate finding carries **evidence**: `path:line`, a measurement (line count, test duration, occurrence count) or a probe transcript. A candidate without evidence is dropped. Done when every check has been applied, with a finding or an explicit "clean".
3. **Probe.** Run the [cold-start probe](#cold-start-probe). Each wrong, incomplete or laborious answer is a candidate finding.
4. **Rank and dedupe.** Rank by how much the problem would cost the next agent starting a ticket. Where an open `hygiene` issue already covers a finding, it becomes a comment on that issue with the new evidence. Keep the top `maxTickets` new findings; the rest go in the summary as "not filed".
5. **File** each kept finding with `gh issue create --label hygiene --title "<area>: <problem>" --body-file - <<'EOF'` using the [ticket template](#ticket-template), and post the dedupe comments with `gh issue comment`.
6. **Summarise.** With a review issue number, post one `gh issue comment <number>` listing: issues filed, issues commented on, findings not filed (one line each), and checks skipped with the reason. Without one, print the same summary. Done when every candidate from steps 2 and 3 appears in exactly one of those lists.

## Checks

### Documentation

- **Consistency:** every command, path, script name and config key a doc mentions exists in the repo (check `package.json` scripts, config files, the directory tree). Docs agree with each other and with the code on behaviour.
- **Length:** any agent-facing doc (`CLAUDE.md`, `AGENTS.md`, files they point at) over `docLineBudget` lines, and any other doc over twice that.
- **Duplication:** one meaning stated in several docs. Name the place that should be the single source of truth.
- **Sediment:** sections describing removed features, finished migrations or past decisions with no remaining bearing.

### Tests

- **Slow:** tests over `slowTestMs`, and the suite total, from the test log. Without a log, skip this check and say so in the summary.
- **Duplicate:** tests asserting the same behaviour through the same path. Cite both.
- **Low value:** tests that assert on mocks they set up, restate the implementation, snapshot incidental output, or cannot fail.
- **Neglected:** skipped, `.only`, retried or commented-out tests.
- **Boundary gaps:** critical workflows spanning UI, API and storage with only unit coverage.

### Entropy

- **Navigation:** files over 500 lines, directories whose contents do not match their name, two patterns in use for one job (two HTTP clients, two state stores, two error styles).
- **Dead weight:** unused exports, files nothing imports, stale feature flags, TODO/FIXME older than the last 20 commits (`git log -S`).
- **Naming drift:** the docs and the code using different names for one concept.

## Cold-start probe

Dispatch one subagent with this brief and nothing else from your context:

> You are starting your first ticket in this repository. Using only what is in the repo, answer: (a) the exact command that runs the full verification, (b) how to run a single test, and (c) for each ticket below, which files you would change first and why. Report each answer with the files you read to reach it.
>
> <the titles and bodies of the 5 recently closed tickets>

Judge the answers against the repo. A finding is any answer that is wrong, misses the files a fix actually touched (`git log --oneline --grep "#<number>"`), or needed more than ~10 files read to reach. Quote the relevant part of the transcript as evidence.

## Ticket template

```markdown
## Problem
<one paragraph: what is wrong and what it costs the next agent>

## Evidence
<paths with line numbers, measurements, probe quotes>

## Suggested change
<the smallest change that removes the problem>

## Acceptance criteria
- [ ] <checkable condition>

Found by hygiene review <#number, or "manual run">.
```

## Configuration

`.claude/hygiene.json` in the project root, written by `/hygiene-setup`. Its presence opts the project into automatic reviews; `{}` takes every default.

| Key | Default | Used by |
| --- | --- | --- |
| `threshold` | `5` | trigger: tickets closed as completed before a review starts |
| `testCommand` | none | trigger: prepares and runs the full suite with per-test durations in a fresh worktree, e.g. `npm ci && npx vitest run --reporter=verbose` |
| `maxBudgetUsd` | `5` | trigger: spending cap for one review |
| `maxTickets` | `5` | this skill: new issues filed per review |
| `docLineBudget` | `200` | this skill: line limit for agent-facing docs |
| `slowTestMs` | `1000` | this skill: duration above which a test counts as slow |
