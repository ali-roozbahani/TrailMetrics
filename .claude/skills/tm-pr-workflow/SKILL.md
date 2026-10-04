---
name: tm-pr-workflow
description: Use for every TrailMetrics task that will end in a commit, push or PR — creating the branch, running the Tier 1 local gate (scripts/pre-push-check.sh), the 2-attempt retry budget, commit message and PR title format, what the PR description must contain, handing Tier 2 to the human, and the standing boundaries (files not to touch as a side effect, no new dependencies, no module-boundary crossing, stating assumptions, following the task's reference pattern). Not for how to write the code itself (see tm-android, tm-ios, tm-kmp-shared, tm-testing) or for planning multi-agent epics.
---

# TrailMetrics PR workflow

This skill is the source of truth for the agent workflow (it replaced the retired
`docs/workflow/coding_agent_workflow.md` and the "Commit, branch & PR discipline" section of
`shared_conventions.md`). It records both the rules and what the repo, the gate script, the
push hook and recent PRs actually do. Where they differ, the repo wins for "what is
enforced", the rules here win for "what the agent should do". Multi-agent epics are covered
in `epic-orchestration`.

The task prompt only says *what* to do. Everything below applies to every task without the
prompt restating it, including committing, pushing and opening the PR: the agent does
those on its own initiative once Tier 1 passes.

## Before starting

- Read `docs/architecture/OVERVIEW.md`, the `README.md` of every module the task touches,
  and `LEARNINGS.md` for known KMP/Xcode/Gradle gotchas.
- Load the code skill(s) for the modules touched (`tm-kmp-shared`, `tm-android`, `tm-ios`,
  `tm-testing`) as well as this one.
- If the task names a board record, read `BOARD.md` first (see "Board").
- Task prompts follow the standard template below. Treat the "should not change" part of
  `Scope` as a hard limit.

```
Task: <one-line description of the feature, fix, or chore>

Context:
- Reference implementation (if porting a feature): <path to the Android or
  iOS equivalent>
- Module(s) this task touches: <list>
- Anything else specific to this task the agent wouldn't otherwise know

Scope:
<what should change, and explicitly what should NOT change>

Branch: <type>/<slug>
```

## Branching

- One feature or fix per branch.
- Create and check out the branch **before the first edit**. Never leave changes on the
  branch you started from, and never commit to `main`.
- Name: `<type>/<slug>`, where type is one of exactly three prefixes:
  - `feature/<slug>`: new functionality
  - `bugfix/<slug>`: fixing a defect
  - `chore/<slug>`: tooling, docs, config, CI, dependency bumps, refactors with no
    behavior change
- Use the name from the task's `Branch:` line. If it uses any other prefix (`docs/`, `ci/`,
  `fix/`, ...), switch to the closest allowed one and say so under "Assumptions" in the PR.
  Precedent: #35 was asked for `docs/...` and used `chore/...`.
- Branch from an up-to-date `main` (`git fetch origin` first) unless the task names a
  different base.
- Slug: lowercase, hyphenated, describes the change (`chore/fix-gate-test-coverage`,
  `bugfix/route-reset-profile-refetch`).

## Tier 1: the local gate (agent's job)

`scripts/pre-push-check.sh` must exit 0 before any push. It always runs the board check
(`scripts/check-board.sh`, also the first step of CI's `android` job), the protected-paths
check (`scripts/check-protected-paths.sh --validate` and `--self-test`, blocking, also the
"Protected paths check" step of CI's `android` job) followed by a report-only line with the
classifier's verdict on the branch's diff (`protected` or `unprotected` and the matching files;
it never fails the gate), the change classification self-test
(`scripts/classify-changes.sh --self-test`), the reviewer workflow self-test
(`scripts/check-pr-review-workflow.sh --self-test`, also the "Reviewer workflow self-test" step
of CI's `android` job: it runs the "Run pr-reviewer" and "Map verdict" scripts of
`.github/workflows/pr-review.yml`, taken from the committed file, against a stub `claude`; it
needs `python3` and `jq` and fails without them) and the iOS scope self-test
(`scripts/check-ios-scope.sh --self-test`, also the "iOS scope self-test" step of CI's `android`
job: it runs the gate's iOS scope block below, extracted from the committed script between its
`# >>> iOS scope: ... (begin) >>>` and `(end)` markers, in scratch git repositories, one case
per fixture in `scripts/check-ios-scope-fixtures/`; it needs `python3`, `bash` and `git` and
fails without them).
The heavy steps run unless
`scripts/classify-changes.sh` decides `light` (non-source changes only; the gate prints the
decision and its files, report only): `detekt`, Android `lint`, `allTests test` and
`assembleDebug`, and the iOS steps below, which also need their path filter. After the tests it also generates the merged
Kover coverage report (`build/reports/kover/`) and prints the line-coverage figure. That
report step is best-effort and never fails the gate. The next step, `koverVerify`, is
enforced: it fails the gate (and CI's android job) when a module drops below its minimum line
coverage. Minimums are set in `domain`, `data` and the three `androidApp` feature modules'
`build.gradle.kts`, a little below each module's measured coverage from its own tests. `core`,
`shared`, `androidApp/app` and `androidApp/core-ui` have no minimum yet. It adds `swiftlint lint --strict`, the shared
XCFramework build (`scripts/build-kmp-framework.sh`, hash-gated), an `xcodebuild` simulator
build and the iOS package tests when the branch's diff touches a file under `iosApp/`, `domain/`,
`data/`, `core/` or `shared/` other than markdown (`*.md`), one of the root Gradle files
`build.gradle.kts`, `settings.gradle.kts`, `gradle.properties` and `gradle/libs.versions.toml`,
one of the files that run the Gradle build (`gradlew`, `gradle/wrapper/gradle-wrapper.jar`,
`gradle/wrapper/gradle-wrapper.properties`, `gradle/gradle-daemon-jvm.properties`), or
`scripts/build-kmp-framework.sh`. Not `gradlew.bat`, `scripts/pre-push-check.sh` itself or
`scripts/classify-changes.sh`; CI's `ios` job runs in full for those (they are not `light`).
The list is `git diff --no-renames -z`, so a move counts with both its paths and no path is
quoted or split. Fail-safe: when the gate cannot read the branch's exact list (no merge-base
with `origin/main`, or `git diff` fails), the iOS steps count as required and a warning prints
why, with the first line of git's error; an empty list read without an error does not count.
When those iOS steps will run, the gate first checks, after the change classification and
before any heavy step, that the git-ignored iOS secrets config (README "iOS", step 2) exists;
if it is missing, the gate stops at once with a non-zero exit, before the heavy steps and the
verdict line. It tests existence only and never reads or creates the file. Its last step prints the `pr-reviewer` verdict recorded for HEAD
(`APPROVE`, `CHANGES` or `ESCALATE_TO_HUMAN`, or that none is recorded); it is report only
and never fails the gate. When and how the session runs the reviewer and records that verdict
(after the last commit, before the gate's final run, again after every new commit) is in
`tm-pr-review`, "Orchestrator's part".

How it is enforced, and what that means for the order of operations:

- A Claude Code `PreToolUse` hook (`.claude/settings.json` →
  `scripts/claude-hooks/block-git-push.sh`) blocks any Bash call containing `git push`
  unless `.git/.pre-push-check-passed` is **newer than the last commit**. So the order is
  always **commit → run the gate → push**. Any new commit (a fix, an amend, a review
  change) needs a fresh gate run before the next push.
- The gate decides whether to run the iOS steps from **committed** changes only
  (`git diff --no-renames <merge-base with origin/main> HEAD`). Uncommitted iOS edits won't trigger
  them, which is one more reason to commit first.
- The hook matches on command text. Any Bash call that merely *mentions* `git push` (a
  commit message or PR body passed inline) is blocked until the gate has passed. Pass long
  text through a file: `git commit -F <file>`, `gh pr create --body-file <file>`.
- `./gradlew test` on its own runs zero tests. KMP tests only run under `allTests`. Use
  the gate script, not a hand-picked Gradle command, and read test counts from `allTests`.
- **Coverage ratchet.** A PR that adds tests to a module with a Kover floor raises that floor
  (`minBound` in its `build.gradle.kts`) in the same PR, to the module's measured line coverage
  (`./gradlew :<module>:koverLog`) minus 1 to 2 points, rounded down. Verify it once: set it 1
  point above the measured value, see `koverVerify` fail for that module, restore. Never lower
  a floor to make a PR pass. If coverage barely moves because the remaining code needs
  infrastructure that isn't available, say so in the PR instead of padding tests.
- A task is not done until Tier 1 has been run **and** its result reported in the PR.

## Retry budget (2 fix attempts)

- One attempt = a change aimed at a gate failure, then a full re-run of
  `scripts/pre-push-check.sh`. The first run doesn't count. If the gate is still red after
  the second fix attempt (third run), **stop**: don't push, and report which step fails,
  the relevant output, and what each attempt changed. Then wait.
- Environment failures are not attempts. Report them right away rather than working
  around them: SwiftLint not installed, no Xcode/simulator, Gradle daemon or network
  errors, a failure that reproduces on a clean `main`.
- Never "fix" a gate failure by editing lint/Detekt/SwiftLint config, adding
  `@Suppress`/`swiftlint:disable`, excluding a test or skipping a step. That trades a gate
  failure for a boundary violation (see Boundaries).
- The budget covers only the local gate loop. It does **not** cover:
  - Review feedback on an open PR. Each requested change is a new commit on the same
    branch, with its own gate run (#31 and #35 each got a second commit this way).
  - Follow-up PRs. #33 → #34 → #35 and #36 → #37 were chains where a PR's findings or a
    reviewer's correction led to a new, separately scoped task. None of them was a gate
    failure: all of #30–#37 were green in CI on the first run.
  - CI going red after a green local gate. That shouldn't happen (see "CI vs the gate"
    below). If it does, report it instead of iterating against CI.

## Tier 2: device verification (human's job)

Running the feature on a simulator, emulator or device and checking it looks and behaves
right is never delegated to the agent. The agent's part is to tell the human exactly what
to check, in the PR description. For docs-, test-, CI- or skill-only changes, say plainly
that there is nothing to check on a device (see #32, #35).

## Commits

- Format: `type(scope): summary`, imperative, lowercase after the colon, no trailing
  period. Explain the *why* in the body when it isn't obvious.
- Types in use: `feat`, `fix`, `refactor`, `build`, `docs`, `test` (the set the retired docs listed),
  plus `chore`, which is the most common type in recent history. Use `chore` for work that fits the `chore/` branch prefix but isn't a
  better fit for `docs`, `build` or `test`.
- Scopes in use: a module or platform (`android`, `ios`, `domain`, `data`, `shared`,
  `core`, `route`) or an area (`ci`, `hooks`, `skills`, `learnings`). Omit the scope
  only when the change really spans everything.
- One type per message. Don't combine them (`docs+chore:` in #7 is not the pattern).
- End every commit message with the attribution trailer the session specifies.

## Push and PR

- Push the branch you created (`git push -u origin <branch>`), then open the PR against
  `main` with `gh pr create --base main`. `gh` must be logged in as an account with write
  access to `ali-roozbahani/TrailMetrics`; check `gh auth status` if `gh` fails.
- Never push to `main`, and never enable GitHub's auto-merge setting. An agent merges only
  under the conditions in `tm-agent-loop` (none before the S6 trial is complete); the
  human merges everything else, after CI is green and Tier 2 has passed.
- **The PR title becomes the commit on `main`.** PRs are squash-merged as
  `<PR title> (#N)`, so the title must itself be a valid `type(scope): summary`.

### PR description

Required. Use these headings, and keep all four even when one is
"nothing to check":

1. **What changed**: the diff in reviewer terms, including what was deliberately *not*
   changed if the Scope named it.
2. **Skills/docs followed**: e.g. `tm-kmp-shared`, `tm-testing`, `tm-pr-workflow`.
3. **Tier 1**: the gate result on the pushed HEAD, which steps ran, and why the iOS steps
   were skipped if they were. For test changes, include test counts before and after
   (from `allTests` JUnit XML, not `./gradlew test`), counted this way:
   - One count per module and test task: each KMP module per target (`domain`, `data`:
     `testAndroidHostTest` and `iosSimulatorArm64Test`; `shared`: `iosSimulatorArm64Test`),
     each Android module's `testDebugUnitTest`.
   - A count is the `tests` attribute summed over the XML files in
     `<module>/build/test-results/<task>/` after the gate's `allTests test` run.
   - Report before and after for each module the PR touches. No repo-wide total.
   - All counts at once:
     `for d in */build/test-results/*/ androidApp/*/build/test-results/*/; do echo "$d $(cat "$d"*.xml | grep -o '<testsuite [^>]* tests="[0-9]*"' | sed 's/.* tests="//; s/"//' | awk '{s+=$1} END {print s+0}')"; done`
4. **Tier 2**: exactly what the human should run and look at on a device, or an explicit
   "nothing to check on a device" and why.

Add these when they apply. Recent PRs use them consistently:

- **Assumptions**: every place the docs were ambiguous and the call you made (see
  Boundaries).
- **Follow-ups (out of scope, not changed)**: problems found but deliberately left alone
  because fixing them would break scope or a boundary. Say what the fix would be. Each
  bullet names its `BOARD.md` record's slug (see "Board").
- **Drift found (not fixed)**: docs that disagree with code this task didn't change (see
  "Docs follow the code you changed" under Boundaries). Each bullet names its `BOARD.md`
  record's slug.
- **Board**: always, as one line: `Board: +slug-a, +slug-b, -slug-c`, or `Board: no changes`.
- **Corrections**: if an earlier PR stated something wrong, correct it explicitly (see
  #34's "Correction to #33").

End the description with the attribution line the session specifies.

## Boundaries

- Never change a protected path as a side effect of an unrelated task. Protected paths
  change only through their own explicitly scoped task and review. The single source of
  truth for which paths are protected is `.github/CODEOWNERS`; there is no list here.
  `scripts/check-protected-paths.sh` classifies a diff from it (`--files <path>...` for
  single paths). If a protected file is wrong, report it under "Follow-ups" instead (#32,
  #33, #34 and #37 all did this).
- An agent never merges a PR that touches a protected path. The human merges those.
- **Docs follow the code you changed.** Before opening the PR, fix in the same PR any line
  in a skill or `CLAUDE.md` that directly describes the current state of the code this
  task changed and is now wrong. That is part of the task, not a side effect, so it needs
  no separate authorization. Drift anywhere else (docs about code this task didn't
  change) is not yours to fix: add a drift record to `BOARD.md` and list it under
  "Drift found (not fixed)" in the PR description, with the line and what the code
  actually does, for a human to decide.
- Never add a third-party dependency (Gradle, SPM or otherwise) unless the task's Scope
  names it. If the task can't be done without one, stop and say so. #34 hit this and
  reported it rather than adding `sqlite-bundled`'s JVM artifact.
- Never cross a module boundary listed in `tm-kmp-shared`. If
  the task seems to need it, stop and report. Don't work around it.
- Never call a deprecated API (details per platform in `tm-android` / `tm-ios`).
- If the docs or conventions are ambiguous or silent on something the task needs, pick the
  most conservative reading and **state it** under "Assumptions". Never choose silently.
- Follow the structure, naming and pattern of the reference that the task's `Context`
  points to. The exception is a reference that hasn't been migrated to its target
  pattern yet. Then follow the target pattern and say so. (All four Android ViewModels
  are on MVI since #54; `tm-android` lists the deviations that remain.)

## Board

`BOARD.md` at the repo root is the backlog of open epics, tasks and drift. A record exists
only while its item is open. Its header gives the record format, including `Order` (unique
integer, ascending = do first, across all sections) and the optional `After` (slugs that must
be gone from the board first). `scripts/check-board.sh` enforces the format; it is the first
step of the gate and of CI's `android` job.

0. **Picking work.** An agent started without a named task takes the record that
   `scripts/check-board.sh --next` prints. If that record is an epic (or
   `figma-design-system`), it starts with the plan under `docs/epics/` for the human to
   approve, not with code.
1. **Add.** Everything you list under "Follow-ups (out of scope, not changed)" or "Drift
   found (not fixed)" gets a record in `BOARD.md` in the **same** PR. The PR description
   keeps those sections, and each bullet names its slug. Every new record gets an `Order`
   and, only if it truly can't start before another record is done, an `After`.
2. **Delete.** When the task starts from a board record, delete that record in the PR that
   does the work, as the last commit before the final push (`chore(board): remove <slug>`).
   A PR closed unmerged never deletes it from `main`. If the work only partly resolves
   the record, narrow its Problem/Done when instead. If the record is obsolete, delete it
   and say why in the PR. The same commit removes the slug from every other record's
   `After` and from every board mention in the skills and docs, or `check-board.sh` fails.
3. **Report.** The PR description gets one line: `Board: +slug-a, +slug-b, -slug-c`, or
   `Board: no changes`.
4. **No board-only PRs.** Never open a PR just to update the board. The human or planner
   passes items found outside a PR into the next task's prompt; add them in that PR. The
   only exception is an epic's final board PR (rule 5).
5. **Epics.** Parallel subtask agents never edit `BOARD.md`, because their edits would
   conflict (this overrides rule 1 for them). They list drift and follow-ups in their PR
   description. Once every subtask is merged into the epic branch, the orchestrator opens
   **one** final board PR into the epic branch. It is not a plan subtask (not in the plan,
   no `allowed_paths`). It adds the records the subtasks reported, deletes the epic's own
   record if the epic started from one, and carries the `Board:` line. It reaches `main`
   with the epic PR, whose own `Board:` line repeats those changes. An epic record points
   to its plan under `docs/epics/`.
6. **Leave other records alone.** Don't delete or rewrite a record you aren't resolving.
   Never rename or renumber a slug. The one exception: a PR may change the `Order` of other
   records only to make room for an insertion, and says so under "What changed".

New slugs are kebab-case, unique in the file and descriptive (never a counter), so two
PRs can't create the same one. A new record goes in the section for its type, at the
position its `Order` gives it (records in a section are sorted by `Order`).

## After the PR is open (human's steps, for context)

1. CI runs on the PR. It should already be green because the gate mirrors it.
2. The human does Tier 2 on a device.
3. The human reviews the structure: does it follow the established pattern, respect module
   boundaries, and avoid duplicating something that should be shared?
4. Only then does the human merge into `main`, unless the PR meets the merge conditions in
   `tm-agent-loop` (none do before the S6 trial is complete). `tm-agent-loop` also has the
   after-merge cleanup and how to read the CI reviewer's verdict.

Review comments turn into new commits on the same branch, each through the gate again.
Answer them in the PR (see #35's comment summarising its second commit) rather than
silently force-pushing.

## Where enforcement and history differ from the rules

- **Branch protection enforces CI but not review.** `main` requires a PR and
  `enforce_admins` is on, so a direct push to `main` is rejected. Both CI checks
  (`Android — Lint, Detekt, Tests, Build` and `iOS — SwiftLint, Build`) are required with
  `strict` on, so a PR can't merge with red CI or while it's behind `main`. The required
  approval count is **0**: review before merge is enforced by the human, not by GitHub
  (#30–#37 were all merged with no review). The required checks were added before #38
  merged.
- **The review check is not required yet.** The `Review — pr-reviewer` check
  (`.github/workflows/pr-review.yml`) runs on PRs, but it is not a required check until S5
  of `docs/epics/agentic-dev-loop.md`.
- **The protected-paths check runs in the gate and in CI** (the "Protected paths check"
  step of CI's `android` job).
- **"Automatically delete head branches" is enabled.** GitHub deletes a PR's remote branch
  when it merges; the local branch is the agent's to delete (`tm-agent-loop`, "After-merge
  cleanup").
- **The gate is a Claude Code hook, not a git hook.** It is a `PreToolUse` hook, so it
  only gates pushes made from a Claude Code session. A push from a terminal skips it.
- **CI doesn't mirror the gate exactly.** CI's heavy steps run unless
  `scripts/classify-changes.sh` decides `light` (non-source changes only; pushes always run
  everything). Unlike the gate, CI's `ios` job has no iOS path filter: on a non-`light` PR it
  runs SwiftLint, the iOS build and the iOS simulator tests even when the gate skipped its iOS
  steps. So an `iosApp/` problem that already existed on `main` can make CI red on an
  unrelated Android-only PR. CI's `android` job runs on Ubuntu, where the iOS simulator tests are
  skipped; they run in the `ios` job since #34.
- **CI only runs on push for `main` and `feature/**`.** `ci.yml`'s push trigger doesn't
  include `bugfix/**` or `chore/**`, so those branches get CI only once the PR is open.
- **Commit types have been used inconsistently.** The retired docs listed only
  `feat`/`fix`/`refactor`/`build`/`docs`/`test`. `chore` is the most-used type since #30,
  and the same kind of change has been typed differently (`chore(ci)` in #33,
  `build(ci)` in #34).
- **The PR description checklist is only partly followed.** #32, #34 and #35 have all four
  items. #33, #36 and #37 have no "Skills/docs followed" and no Tier 2 line, and #30/#31
  follow neither. This skill makes all four headings mandatory.
- **Branch prefixes were looser before #30.** `docs/` (#10, #27), `ci/` (#5) and `phase-*`
  (#1, #2) branches exist in history. Since #30 every branch is `feature/`, `bugfix/` or
  `chore/`.
- **Three commits reached `main` without a PR** (`0add288`, `0ff3ccc`, `6c37a62`, all on
  2026-09-19). That was before #30 turned on the current protection. Every change since
  has gone through a PR.
- **The Boundaries list is wider than `CLAUDE.md`'s.** `CLAUDE.md` lists
  `docs/architecture`, CI, lint config and itself. It doesn't list the gate script, the
  hook, `.claude/settings.json` or the skills. This skill adds those (assumption: they're
  as load-bearing as CI config).
- **The retry budget was never defined precisely.** The retired workflow doc said
  "2 fix attempts" without defining an attempt or saying whether review rounds and
  follow-up PRs count. The definition above is this skill's reading. GitHub doesn't record
  local gate failures, so recent PRs can't show how often the budget is actually hit.
