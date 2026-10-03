# Live verification dashboard

For a new software project with automated build or test workflows, include a repository-owned live verification dashboard in the initial testing infrastructure. In an existing project without one, add it only when the ticket materially changes the build or test workflow.

The canonical verification command remains the source of truth. The dashboard is observational and must preserve gate order, output, pass/fail semantics, and exit status.

For interactive local full verification:

- Start a localhost-only dashboard automatically and print its exact URL as `TEST_DASHBOARD_URL`.
- Show the active stage, available per-test progress, elapsed time, recent output, failures, and final result.
- Prefer a documented stable URL; isolate concurrent runs by selecting a free port or equivalent and print every non-default URL.
- Run full verification as a yielded or background-capable process. Open or focus the dashboard immediately in the built-in browser pane, including as soon as a dynamically assigned URL appears, then keep waiting on verification. If no browser opener is available, surface the clickable URL and continue in the terminal.

Keep focused tests lightweight without opening the dashboard. Keep CI headless; it may emit a static report artifact.

Use runner-native lifecycle reporters or structured event hooks where available. Dashboard server, reporter, and browser-display failures must fall back to normal terminal output without changing verification success or failure.

Document the command, URL and port behavior, CI behavior, opt-out mechanism, and framework integration. Add focused automated coverage for the event/state model, server endpoints, verification-profile ordering, reporter degradation, and concurrent runs.
