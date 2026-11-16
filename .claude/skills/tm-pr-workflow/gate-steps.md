# Tier 1: what the gate does, bullet by bullet

Moved word for word from `SKILL.md`, "Tier 1: the local gate" (the bullets from "`light` or full" to "Reviewer verdict"). The rules are unchanged; `SKILL.md` keeps their headline.

- **`light` or full.** `scripts/classify-changes.sh` decides. `light` means no changed file can
  affect the Android or iOS build or their tests: docs, skills and agent files, CODEOWNERS, the
  reviewer's workflow and the tooling scripts under `scripts/`, except the scripts on its
  `HEAVY_SCRIPTS` list (the ones a CI build or test step starts, the classifier, CI's helpers and the
  self-tests only the iOS job runs) and, for the gate only, its `GATE_ONLY_HEAVY_SCRIPTS` list (the gate,
  `heavy-run.sh`, `filter-xcode-log.sh`, `scrub-env.sh`: nothing in CI runs them, and their self-tests run in
  the always-run tooling job, so CI calls them light and the gate calls them full); a heavy script's reason is
  in the comment above its list. `scripts/check-heavy-scripts.sh` (a gate step, and run first by the CI classification)
  fails when a script that a build or test step runs is not on the list (and when a CI step runs a gate-only one): add it to `HEAVY_SCRIPTS`. On `light`
  the gate skips the Gradle build and test steps and the iOS steps; the checks that need
  no build, among them the Kover floors and Room schema checks, still run. A full run adds the
  iOS steps when the committed diff touches iOS or shared code, or when the gate cannot read the
  diff. A skipped step is not a pass: the PR's Tier 1 says which steps ran and why the rest did not.
- **Self-test of a new script.** Its `--self-test` goes on one of the two lists the gate and CI read
  (`scripts/checks/self-tests.sh` reads both): group `tooling` (CI's `tooling` job) on
  `scripts/checks/self-tests-tooling.list`, which `scripts/classify-changes.sh` treats as light, so
  a PR of tooling scripts and their registration stays light; an iOS group (CI's `ios-build` job) on
  `scripts/checks/self-tests.list`, a heavy file, when the script tests iOS-only things. Never into the
  Android build job; a job's name states what the job runs. `scripts/checks/self-tests.sh --check` fails
  on a script that has a self-test and is on neither list, and on another group in the tooling list.
- **A shallow clone.** The gate's first check, `scripts/check-full-clone.sh`, stops the gate before any
  step when the clone is shallow (CI's checkout is exempt); the fix is `git fetch --unshallow`. No
  script fetches at depth in a full clone: `scripts/check-board.py` and `scripts/ci/pr-base.sh` do it
  only when the checkout is already shallow, so setting CI's variables by hand is safe.
- **A failing step** (a timeout of a UI-test step counts) fails the gate, which prints
  the failed steps and "Do not push". Fix it within the "Retry budget".
- **Secrets.** Never pass a secret (the Maps key among them) on an `xcodebuild` command line:
  `xcodebuild` echoes its arguments, and the gate's log filter hides only Xcode's
  exported-environment lines. The iOS secrets config (README "iOS", step 2) is git-ignored; when
  the gate stops because it is missing, never read, print, create or commit it: stop and
  report.
- **One heavy run at a time.** The gate starts itself under `scripts/heavy-run.sh`, the
  machine-wide lock for Gradle and xcodebuild runs: when another heavy run is going, the gate
  prints who it waits for and starts when that run ends. Any other Gradle or `xcodebuild` command
  the agent starts goes through `scripts/heavy-run.sh <command>` too (two at once took twice as
  long each and pushed swap up on this Mac). A wait is not a failure and not an attempt.
- **Coverage.** `koverVerify` fails the gate when a module is below its minimum in
  `config/kover-floors.properties`; see "Coverage ratchet". A module with no floor gets one when
  its first test of its own runs on the Android host.
- **Room schema.** `scripts/check-room-schema.sh --base <merge-base>` runs in every
  classification: schema files under `data/schemas/` are append-only, a version bump needs its
  schema file, `MIGRATION_M_N` and a test naming it, and `data/src/*Main/` has no
  `fallbackToDestructiveMigration`. The build must leave `data/schemas/` unchanged (a modified,
  deleted or untracked file there fails the gate).
- **Reviewer verdict.** Every push needs the local `pr-reviewer` verdict for HEAD recorded
  first, `light` or full, docs-only or not, whatever CI's reviewer will run. The gate prints it
  and never fails on it, but the push hook refuses a push (exit 2) unless the record is
  `APPROVE` or `ESCALATE_TO_HUMAN` for HEAD; "no review verdict recorded" means you have not
  run it: go back. A second hook, `scripts/claude-hooks/require-local-review.sh`, also blocks
  `git push` and `gh pr create` unless the reviewer's own report for the commit that would be
  pushed (the pushed ref resolved to a SHA: `git push origin other:branch` needs the review of
  `other`) allows it; "Push and PR" says how to satisfy it. A terminal push by the human is not seen by the hook, unchanged. When to run it and record it (after the last commit, before the gate's final run, again after
  every new commit) is in `tm-pr-review`, "Orchestrator's part".
