# scripts/

One line per script. `scripts/checks/scripts-index.sh --check` (gate and CI's `tooling` job) fails
when a `*.sh` or `*.py` file under `scripts/` (outside `*-fixtures/` folders) has no line here, or
a line names a file that does not exist. Each script's header says how to run it.

## The gate

- `scripts/pre-push-check.sh`: the local gate; must pass before any push (`tm-pr-workflow`, "Tier 1"). It prints one line per step and keeps each step's full log in `~/agent-workspace/gate-logs/<run>/` (a failed step also prints its failure block).
- `scripts/heavy-run.sh`: runs one heavy command (Gradle, xcodebuild, the gate) under the machine-wide lock, so only one runs at a time; a run that waits says for how long, and every run appends to an event log (`--log`).
- `scripts/android-ui-tests.sh`: runs the Android instrumented tests (`androidApp/app/src/androidTest`) once on a dedicated headless AVD of its own (`TrailMetrics_UITest`, port 5560, `ANDROID_SERIAL` pinned; the developer's emulators are never touched), under `heavy-run.sh`; prints the pins of the run; `--tests <class>` runs one class. The gate runs it when the diff's UI scope includes Android (`tm-testing`, "Rules for `androidTest`").
- `scripts/ios-ui-tests.sh`: runs the iOS UI tests (scheme `TrailMetricsUITests`, all of them or `--tests <Class[/method]>`) once on a dedicated simulator of its own (`TrailMetrics_UITest`, pinned to the iPhone 17 device type and the iOS 26.5 runtime, shut down and erased before each run; other simulators are never touched); builds the test-only framework variant, filters the log, prints the pins of the run; no retry. The gate runs it, under `heavy-run.sh`, when the diff's UI scope includes iOS (`tm-testing`, "Which test goes where").
- `scripts/run-limited.sh`: `<seconds> <command>...` runs a command with a hard time limit and kills its process group when it is hit (exit 124); the gate's and the main run's UI-test steps use it.
- `scripts/main-ui-run.sh`: the full UI run of both platforms on `origin/main`, decided by the script (`--auto`, `--due`, `--status`, `--run`, `--release`): due when main has code changes since the last full run, whose SHA it keeps, and before a release; a red keeps the logs and adds the queue entry `main-ui-red-<sha>` (`tm-agent-loop`, section 9).
- `scripts/ui-flake.sh`: records every UI-test run of the gate and of the main run (`--record`) and detects a local flake by itself: a pass after a failure on the same platform with no change in that platform's UI scope in between; `--pending`, `--pending-count`, `--logged <id>`. Counted and logged like a CI flake, never retried (`tm-pr-workflow`, "Flake log", "Local UI flakes").

## Checks of a diff (gate and CI)

- `scripts/classify-changes.sh`: decides `light` or `full` for the gate and CI (and, with `--ui-scope`, which platform's UI tests a diff needs: android, ios, both or none; docs, skills, tooling scripts and workflow files are none) (a tooling-only change is light; its HEAVY_SCRIPTS list names the scripts that stay full, its GATE_ONLY_HEAVY_SCRIPTS list those that stay full for the gate and are light in CI; `--ci` classifies as CI does).
- `scripts/check-workflow-guard.sh`: the gate step that keeps the agent from pushing a change only the owner pushes: a diff touching `.github/workflows/pr-review.yml`, or adding a reference to `secrets` in any workflow file, fails; every other workflow change passes (`tm-agent-loop`, section 5). `--base <ref>`; `--self-test`.
- `scripts/check-full-clone.sh`: fails on a shallow clone (CI's checkout is exempt); the gate's first check, with the fix.
- `scripts/check-ci-triggers.sh`: the gate step that fails when a `push` trigger of a workflow names a branch that can have a pull request (only `main` may); `--self-test` runs its fixtures and the committed workflows, so CI's tooling job enforces it too.
- `scripts/check-ci-triggers.py`: the logic of `check-ci-triggers.sh`.
- `scripts/check-heavy-scripts.sh`: fails when a script that a build or test step runs is not on that list, or a CI step runs a gate-only one.
- `scripts/check-heavy-scripts.py`: the logic of `check-heavy-scripts.sh`.
- `scripts/check-board.sh`: `BOARD.md`'s record format, Order/After, dangling mentions, and (`--base`) a deleted record's slug still named elsewhere; `--next` prints the record to take.
- `scripts/check-board.py`: the implementation behind `check-board.sh`.
- `scripts/check-protected-paths.sh`: classifies a diff or files as protected from `.github/CODEOWNERS`; `--validate` checks the file.
- `scripts/check-protected-paths.py`: the implementation behind `check-protected-paths.sh`.
- `scripts/check-kover-floors.sh`: the Kover floors in `config/kover-floors.properties` only go up.
- `scripts/check-kover-floors.py`: the implementation behind `check-kover-floors.sh`.
- `scripts/swiftlint-pin.sh`: the pinned SwiftLint version (`config/swiftlint.pin`): `--check` for the gate, `--install <dir>` for CI (sha256 verified); `--self-test`.
- `scripts/check-no-println.sh`: fails on a `println(` or `print(` in production Kotlin, which detekt cannot see; `--self-test`.
- `scripts/check-room-schema.sh`: Room schema files are append-only, a version bump has its migration and test.
- `scripts/check-room-schema.py`: the implementation behind `check-room-schema.sh`.
- `scripts/check-skill-rule-changes.sh`: lists removed or rewritten rule lines in skills and `CLAUDE.md` files.
- `scripts/check-skill-rule-changes.py`: the implementation behind `check-skill-rule-changes.sh`.
- `scripts/check-ios-scope.sh`: self-test of the gate's iOS scope block.
- `scripts/check-ios-scope.py`: the implementation behind `check-ios-scope.sh`.
- `scripts/check-pr-review-workflow.sh`: self-test of `pr-review.yml`'s scripts and of `review-task.sh` against them.
- `scripts/check-pr-review-workflow.py`: the implementation behind `check-pr-review-workflow.sh`.
- `scripts/check-variant-api.sh`: the test-only framework variant's API against production's.
- `scripts/check-production-framework.sh`: no test-only Kotlin in the production framework.
- `scripts/check-localized-strings.sh`: self-test of the SwiftLint rules against hardcoded user-visible strings.
- `scripts/check-optional-try.sh`: self-test of the SwiftLint `optional_try` rule.
- `scripts/checks/self-tests.sh`: runs and checks the lists of script self-tests, `scripts/checks/self-tests-tooling.list` (light) and `scripts/checks/self-tests.list` (the groups only the iOS job runs, heavy).
- `scripts/checks/scripts-index.sh`: checks this index against the scripts under `scripts/`.

## Review and PR description

- `scripts/review-task.sh`: prints the local `pr-reviewer`'s message, as CI's reviewer gets it.
- `scripts/local-review-gate.sh`: records the local reviewer's report per commit and decides whether a push is allowed.
- `scripts/local-review-prepare.sh`: fills the review input directory and writes the reviewer's whole message to a file in it.
- `scripts/local-review-record-verdict.sh`: writes `.review-verdict` from the reviewer's recorded report after checking its format.
- `scripts/skill-changes-digest.sh`: what changed in the skills and `CLAUDE.md` files on `main` since a date.
- `scripts/set-pr-body.sh`: sets a PR's description from a file through the REST API.
- `scripts/review-input-check.sh`: a mechanical copy of the reviewer's input checks; its self-test runs them on a clone, a worktree and the tree CI builds.

## CI: after a push

- `scripts/ci/pr-base.sh`: the PR's base commit for CI's base-comparing steps (validated, fetched when missing).
- `scripts/wait-for-checks.sh`: waits for a commit's check runs (`--review-first` for the reviewer's).
- `scripts/read-ci-verdict.sh`: the CI reviewer's verdict from its check run's annotation.
- `scripts/rerun-failed-once.sh`: re-runs a finished run's failed jobs, once.
- `scripts/cancel-head-ci.sh`: cancels the unfinished runs of an open PR's current head when a reviewer finding is going to be fixed.
- `scripts/main-ci-status.sh`: the last push runs on `main`; `--ack` records an acknowledged red run.

## The PR queue (local, serial)

- `scripts/queue/queue.sh`: the queue file of follow-up PRs; `next` says what to build, push or wait for.
- `scripts/queue/watch-prs.sh`: the bot's open PRs once, or waits for the first merge, close, new head, fall-behind or finished checks.
- `scripts/queue/update-branch.sh`: asks GitHub to update a PR branch that fell behind and checks the update is merge-only.
- `scripts/queue/merge-only-check.sh`: proves a merge commit only moved its branch's base.
- `scripts/queue/local-verdict-for-head.sh`: the local review that holds for a PR head over merge-only updates.

## Subagents (the orchestrator's tools, `tm-agent-loop`, "Subagents")

- `scripts/subagent/worktree.sh`: creates an implementer's git worktree from a local branch with its allowed paths, takes its commits back into the task branch, removes it.
- `scripts/subagent/guard.sh`: the implementer's own PreToolUse hook (its agent file names it): keeps it in its worktree and allowed paths, off push, `gh` and the orchestrator's scripts. Records every call and block in a log the orchestrator reads with `--log`.

## Claude Code hooks (named by `.claude/settings.json`)

- `scripts/claude-hooks/block-git-push.sh`: blocks a push or PR creation without a fresh gate pass, a verdict and the `gh` credential helper.
- `scripts/claude-hooks/require-local-review.sh`: records the local reviewer's report; blocks a push or PR creation it does not allow.
- `scripts/claude-hooks/block-branch-create-while-merged-branches.sh`: blocks a new branch while merged local branches remain.

## Build and local tools

- `scripts/build-kmp-framework.sh`: builds the KMP XCFramework for iOS when its inputs changed (Xcode build phase, gate, CI).
- `scripts/filter-xcode-log.sh`: drops Xcode's environment dumps from `xcodebuild` output.
- `scripts/scrub-env.sh`: removes secret-looking variables from the environment (sourced by the gate).
- `scripts/prune-merged-branches.sh`: deletes the local branches whose PR is merged.
- `scripts/simulate-route.sh`: walks an iOS Simulator along a GPS route from `scripts/routes/`.
- `scripts/dev/clean-agent-workspace.sh`: deletes the agent workspace's loose files of any name (drafts, logs, scratch scripts, diffs) and review records of finished work older than 3 days, and inside `queue/` the task texts of merged or dropped entries and the log lines of the guard and the heavy-run lock older than 3 days. It never deletes state or what an open entry of the PR queue uses, and runs at the start of a task and whenever `queue.sh set` records an entry as merged or dropped.
