# scripts/

One line per script. `scripts/checks/scripts-index.sh --check` (gate and CI's `tooling` job) fails
when a `*.sh` or `*.py` file under `scripts/` (outside `*-fixtures/` folders) has no line here, or
a line names a file that does not exist. Each script's header says how to run it.

## The gate

- `scripts/pre-push-check.sh`: the local gate; must pass before any push (`tm-pr-workflow`, "Tier 1").

## Checks of a diff (gate and CI)

- `scripts/classify-changes.sh`: decides `light` or `full` for the gate and CI.
- `scripts/check-board.sh`: `BOARD.md`'s record format, Order/After, dangling mentions, and (`--base`) a deleted record's slug still named elsewhere; `--next` prints the record to take.
- `scripts/check-board.py`: the implementation behind `check-board.sh`.
- `scripts/check-protected-paths.sh`: classifies a diff or files as protected from `.github/CODEOWNERS`; `--validate` checks the file.
- `scripts/check-protected-paths.py`: the implementation behind `check-protected-paths.sh`.
- `scripts/check-kover-floors.sh`: the Kover floors in `config/kover-floors.properties` only go up.
- `scripts/check-kover-floors.py`: the implementation behind `check-kover-floors.sh`.
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
- `scripts/checks/self-tests.sh`: runs and checks the one list of script self-tests, `scripts/checks/self-tests.list`.
- `scripts/checks/scripts-index.sh`: checks this index against the scripts under `scripts/`.

## Review and PR description

- `scripts/review-task.sh`: prints the local `pr-reviewer`'s message, as CI's reviewer gets it.
- `scripts/local-review-gate.sh`: records the local reviewer's report per commit and decides whether a push is allowed.
- `scripts/local-review-prepare.sh`: fills the review input directory and writes the reviewer's whole message to a file in it.
- `scripts/local-review-record-verdict.sh`: writes `.review-verdict` from the reviewer's recorded report after checking its format.
- `scripts/skill-changes-digest.sh`: what changed in the skills and `CLAUDE.md` files on `main` since a date.
- `scripts/set-pr-body.sh`: sets a PR's description from a file through the REST API.

## CI: after a push

- `scripts/ci/pr-base.sh`: the PR's base commit for CI's base-comparing steps (validated, fetched when missing).
- `scripts/wait-for-checks.sh`: waits for a commit's check runs (`--review-first` for the reviewer's).
- `scripts/read-ci-verdict.sh`: the CI reviewer's verdict from its check run's annotation.
- `scripts/rerun-failed-once.sh`: re-runs a finished run's failed jobs, once.
- `scripts/main-ci-status.sh`: the last push runs on `main`; `--ack` records an acknowledged red run.

## The PR queue (local, serial)

- `scripts/queue/queue.sh`: the queue file of follow-up PRs; `next` says what to build, push or wait for.
- `scripts/queue/watch-prs.sh`: the bot's open PRs once, or waits for the first merge, close, new head, fall-behind or finished checks.
- `scripts/queue/update-branch.sh`: asks GitHub to update a PR branch that fell behind and checks the update is merge-only.
- `scripts/queue/merge-only-check.sh`: proves a merge commit only moved its branch's base.
- `scripts/queue/local-verdict-for-head.sh`: the local review that holds for a PR head over merge-only updates.

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
- `scripts/dev/clean-agent-workspace.sh`: deletes the agent workspace's drafts, logs and review records of finished work older than 3 days.
