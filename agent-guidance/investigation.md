# Bounded investigative work

Use this loop for optimisation, debugging, performance regressions, and other open-ended investigations:

1. Before a substantive change, establish the best reproducible baseline, an observable success criterion and target, and a measurement method with known reliability limits.
2. For each substantive attempt, record: **hypothesis → change → measurement → conclusion**. An attempt is substantive when it tests a distinct hypothesis or materially changes code, configuration, dependencies, or architecture; minor corrections and additional observations do not count separately.
3. Count progress only when evidence moves toward the target or reliably reduces uncertainty enough to change the next step.
4. After three consecutive attempts without progress, pause and reassess the hypothesis, measurement reliability, architectural approach, and need for human judgement or more information. Resume only with a clearly different hypothesis or approach.
5. Stop after five unsuccessful substantive attempts against the same success criterion unless the user explicitly authorises more investigation.

When stopping, report the baseline and target, approaches tried, measurements and results, current best explanation, and recommended next steps.

Keep the investigation log in task updates or temporary notes. Add a tracked file only when requested or clearly useful as lasting project documentation.
