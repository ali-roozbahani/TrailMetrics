# Flake log

Moved word for word from `SKILL.md`, "Flake log". The rules are unchanged; they are still cited as `tm-pr-workflow`, "Flake log".

`CI_FLAKES.md` at the repo root logs CI flakes; the agent edits it (its header gives the entry
format). It is not protected, and a PR that touches only that file is not a board-only PR.

- One entry per signature: job, step, test, first error line, short slug. A re-run that turns
  green adds an occurrence (date, run id, PR, re-run fixed it) and increments the count; a new
  signature is a new entry, count 1, status `open`.
- **Local UI flakes** (owner decision of 2026-11-15; the UI tests run in the gate and in the full run on `main`,
  not in CI). There is no automatic retry, anywhere: a failed UI-test step fails the gate (or is a red full run),
  and the next run is a new run. `scripts/ui-flake.sh` records every UI-test run of the gate and of
  `scripts/main-ui-run.sh` (commit, platform, result, the failure's signature) and detects the flake by itself:
  a pass whose previous run on the same platform failed, on the same commit or on a later one whose changes
  since then are not in that platform's UI scope (`classify-changes.sh --ui-scope`). A pass after a change in
  that scope is a fix, not a flake. A detected flake is printed by that run, listed in the gate's report-only
  step "local UI flakes not yet logged" and counted by `scripts/main-ui-run.sh --status` until it is logged.
  Logging it is the CI flake rule with these differences: the **job** is `local gate: <Android|iOS> UI tests`
  or `local main run: <Android|iOS> UI tests` (the run where it failed), the step and test and first error line
  are the signature the script printed, "re-run: no" (the next run that passed was not a re-run), the run id
  is the commit and the time. One entry per signature, the count, the escalation at count 3 to a `BOARD.md`
  record and the `fixed (unverified)` / `fixed` rules are unchanged. After adding the occurrence run
  `scripts/ui-flake.sh --logged <id>`. A pending flake blocks nothing; where the update goes is the next bullet.
- Where the update goes. A PR that is already green, or being merged, never gets a push for a
  flake-log update: it would start another full CI cycle for it. The update of a run of such a PR
  goes into the first queue entry that is not pushed yet (its "What changed" says so), else into a
  small PR of its own (`chore/flake-log-<slug>`, a queue entry; light CI). The update of a run of a
  PR that is still red or waiting for a fix may go into that PR when a push is happening anyway.
  The agent may merge a PR that touches only `CI_FLAKES.md` once the merge conditions of
  `tm-agent-loop`, section 8 (`merge.md`) hold.
- At count 3 for an `open` entry, add a `BOARD.md` record in the PR you are working on (type
  task, slug `flake-<slug>`, Problem with the occurrences, Done when: the flake no longer fails
  or the runner/test is changed so it cannot, shown on 5 consecutive runs) and mark the entry
  `escalated: flake-<slug>`. At most one record per entry. The exception: a failure of the kind
  "job not acquired by a runner" (the runner never started the job, so no test and no code is involved: infra)
  is counted and never escalates, at count 3 or any other: no record and no `escalated:` line. The owner
  decides on pinning the runner label when the count shows a pattern (the entry `ios-2a-job-not-acquired` of
  `CI_FLAKES.md` is the one for the macOS jobs).
- The PR that fixes a flake sets the entry to `fixed (unverified)`, the status of a board record
  until its Done when is shown, with `Fix: #<PR number>` (the number once the PR exists, never the
  branch name) and one line of what was learned, deletes the `BOARD.md` record, and adds an entry
  to `LEARNINGS.md` (why it flaked, what fixed it). The entry becomes `fixed` once 5 consecutive
  runs of its job on `main` after the fix's merge commit are green (`scripts/main-ci-status.sh
  --recent 10`; a run that skipped the job does not count). The first later PR that touches
  `CI_FLAKES.md` makes that change. A failure with the signature of a `fixed (unverified)` or
  `fixed` entry reopens it: status `open`, the occurrence added, the count incremented.
