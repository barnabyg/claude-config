# Code verification

Treat repository build scripts and tool configuration as the source of truth. Before changing code, discover and use the existing quality tools. Add an analyzer only for a demonstrated gap and avoid redundant or conflicting checks.

Every project containing executable code must provide one canonical, non-mutating verification command covering all applicable gates in this order:

1. Formatting check.
2. Lint and style analysis.
3. Compiler and type checking.
4. Static bug analysis.
5. Automated tests.
6. Dependency, vulnerability, secret, and package checks.
7. Build or packaging validation.

When creating a project or introducing a language, choose maintained ecosystem-native tools, pin their versions, commit their configuration, integrate every gate into the canonical command and CI, and document any inapplicable gate.

Configure warnings as errors wherever supported. Run focused checks during implementation. Before handoff, the full canonical command must pass on the exact commit being handed off: in a green CI run that covers every gate, or locally when the global pre-push rule requires a local run. Continue remediation until it passes with no errors, unresolved diagnostics, actionable or unsuppressed warnings, formatting violations, test failures, or undocumented suppressions. A passing exit code with unresolved warning output is a failure.

Treat every warning as work. Either fix its underlying cause or add a narrow documented exception that:

- names the exact rule or diagnostic;
- applies at the smallest possible scope;
- gives the technical justification beside the suppression or in the designated exception file;
- removes the diagnostic from normal verification output; and
- states a review condition or expiry where the justification may become obsolete.

Broad exclusions, blanket suppressions, warning-count baselines, and grandfathered violations are not compliant. When adopting the gates in a legacy project, resolve existing violations rather than baselining them.

Report the canonical command or CI run, its result, and every exception added or changed.
