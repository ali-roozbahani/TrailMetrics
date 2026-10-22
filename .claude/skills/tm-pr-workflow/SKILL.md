---
name: tm-pr-workflow
description: Use for every TrailMetrics task that will end in a commit, push or PR — creating the branch, running the Tier 1 local gate (scripts/pre-push-check.sh), the 2-attempt retry budget, commit message and PR title format, what the PR description must contain, Tier 2 (the automated test for each user-visible behavior, or a human check with its reason), and the standing boundaries (files not to touch as a side effect, no new dependencies, no module-boundary crossing, stating assumptions, following the task's reference pattern). Not for how to write the code itself (see tm-android, tm-ios, tm-kmp-shared, tm-testing) or for planning multi-agent epics.
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

Every run starts with these steps, for a named task and a board pick alike:

```bash
gh api user --jq .login          # must print peter-christofer-bot
cd ~/agent-workspace/TrailMetrics
git status --porcelain           # must be empty
git fetch --prune origin && git switch main && git pull --ff-only
git branch -vv                   # every branch other than main is from an earlier run
```

- Anything else (another login or clone, a dirty tree, a pull that can't fast-forward): stop
  and report.
- For each local branch other than `main`, look up its PR
  (`gh pr list --head <branch> --state all --json number,state`). `MERGED`: delete it with
  `git branch -D <branch>` (a squash merge is not "merged" for git). `OPEN` or no PR: leave it
  and name it in the report. GitHub deletes the remote branch itself ("Automatically delete
  head branches" is on).
- Create the task's branch from this local `main` (see "Branching").

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
- Branch from the local `main` that "Before starting" left equal to `origin/main`, never from
  `origin/main` directly, unless the task names a different base.
- Slug: lowercase, hyphenated, describes the change (`chore/fix-gate-test-coverage`,
  `bugfix/route-reset-profile-refetch`).

## Tier 1: the local gate (agent's job)

`scripts/pre-push-check.sh` must exit 0 before any push. The script is the description of the
gate: its header comment, its output (it names every step that ran) and the `--self-test`
option of each `scripts/check-*.sh` script say what is checked, so read them rather than a list
here. Run the script itself, not a hand-picked command.

- **`light` or full.** `scripts/classify-changes.sh` decides. On `light` (non-source changes
  only) the gate skips the Gradle build and test steps and the iOS steps; the checks that need
  no build, among them the Kover floors and Room schema checks, still run. A full run adds the
  iOS steps when the committed diff touches iOS or shared code, or when the gate cannot read the
  diff. A skipped step is not a pass: the PR's Tier 1 says which steps ran and why the rest did not.
- **A failing step** (a timeout of the iOS smoke UI test counts) fails the gate, which prints
  the failed steps and "Do not push". Fix it within the "Retry budget".
- **Secrets.** Never pass a secret (the Maps key among them) on an `xcodebuild` command line:
  `xcodebuild` echoes its arguments, and the gate's log filter hides only Xcode's
  exported-environment lines. The iOS secrets config (README "iOS", step 2) is git-ignored; when
  the gate stops because it is missing, never read, print, create or commit it: stop and
  report.
- **Coverage.** `koverVerify` fails the gate when a module is below its minimum in
  `config/kover-floors.properties`; see "Coverage ratchet". A module with no floor gets one when
  its first test of its own runs on the Android host.
- **Room schema.** `scripts/check-room-schema.sh --base <merge-base>` runs in every
  classification: schema files under `data/schemas/` are append-only, a version bump needs its
  schema file, `MIGRATION_M_N` and a test naming it, and `data/src/*Main/` has no
  `fallbackToDestructiveMigration`. The build must leave `data/schemas/` unchanged (a modified,
  deleted or untracked file there fails the gate).
- **Reviewer verdict.** The gate prints the recorded `pr-reviewer` verdict for HEAD and never
  fails on it. When the session runs the reviewer and records the verdict (after the last
  commit, before the gate's final run, again after every new commit) is in `tm-pr-review`,
  "Orchestrator's part".

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
  (its entry in `config/kover-floors.properties`, which its `build.gradle.kts` reads) in the
  same PR, to the module's measured line coverage
  (`./gradlew :<module>:koverLog`) minus 1 to 2 points, rounded down. Verify it once: set it 1
  point above the measured value, see `koverVerify` fail for that module, restore. Never lower
  a floor to make a PR pass. If coverage barely moves because the remaining code needs
  infrastructure that isn't available, say so in the PR instead of padding tests.
  `scripts/check-kover-floors.sh` (gate and CI) fails when a floor is lower than on the base,
  when a module whose `build.gradle.kts` reads the file has no entry, when an entry has no
  such module, and when a floor's entry is gone while the module that held it still exists.
  Lowering a floor is not supported by the mechanism: it needs a human PR that
  changes the script. A new module's first floor is a new entry plus the same read in its
  `build.gradle.kts`.
- A task is not done until Tier 1 has been run **and** its result reported in the PR.

## Retry budget (2 fix attempts)

- One attempt = a change aimed at a gate failure, then a full re-run of
  `scripts/pre-push-check.sh`. The first run doesn't count. If the gate is still red after
  the second fix attempt (third run), **stop**: don't push, and report which step fails,
  the relevant output, and what each attempt changed. Then wait.
- Every stop-and-report, and the final report of a run, has the shape in `tm-agent-loop`, "Report".
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

## Tier 2: what automated tests cannot show

The user-visible behavior of a change (a screen, a ViewModel state, a navigation, a
notification text), on each platform it touches, is validated by automated tests: unit,
integration and UI tests (`tm-testing`), not by a human on a device. The agent has no device
and never runs the feature on one itself. A human check is listed only for one of these
reasons:

1. **No automated test can observe it.** In this repo: real GPS hardware and the platform
   location providers (every test uses a fake `LocationRepository`); what the real Maps SDK
   draws (Compose UI tests show the map as an empty `Box` or a shadowed `MapView`, and the
   map's content is not asserted, on iOS either); OS-level permission dialogs, the
   tracking notification and the iOS Live Activity (`TrackingWidget`); and a human judgement
   of visual design against Figma.
2. **A test seam or test target that does not exist yet.** It must be tracked by a
   `BOARD.md` record that the PR names. The iOS UI-test target `TrailMetricsUITests` has a
   launch test and the failed-delete test, and the app has its launch-time fake seam (the
   `UITEST_SEAM` entry); the other scenarios land with later subtasks of
   `docs/epics/ios-ui-tests.md`, so an iOS-only user-visible behavior whose logic no Swift unit
   test in the packages covers and no scenario reaches may still need this.
3. **The single final smoke check of a finished end-to-end feature**, after all its automated
   tests passed. It is a smoke check, not the validation.

For each human check the PR gives the behavior, the reason (1, 2 with the record's slug, or
3) and the exact steps. For docs-, test-, CI- or skill-only changes, say plainly that nothing
user-visible changes (see #32, #35).

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
  under the conditions in `tm-agent-loop`; the human merges everything else, after CI is
  green and Tier 2 has passed (every human check the PR lists is done). A human check
  listed under Tier 2 does not block a merge the agent makes: it stays in the PR's
  description, and the human does it when testing the feature (the epic-level Tier 2),
  not before the merge.
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
     `testAndroidHostTest` and `iosSimulatorArm64Test`; `shared` and `shared-uitest`:
     `iosSimulatorArm64Test`),
     each Android module's `testDebugUnitTest`.
   - A count is the `tests` attribute summed over the XML files in
     `<module>/build/test-results/<task>/` after the gate's `allTests test` run.
   - Report before and after for each module the PR touches. No repo-wide total.
   - All counts at once:
     `for d in */build/test-results/*/ androidApp/*/build/test-results/*/; do echo "$d $(cat "$d"*.xml | grep -o '<testsuite [^>]* tests="[0-9]*"' | sed 's/.* tests="//; s/"//' | awk '{s+=$1} END {print s+0}')"; done`
4. **Tier 2**: for each user-visible behavior the change alters, the automated test that
   covers it (by name), or a human check with its reason and steps (see "Tier 2: what
   automated tests cannot show"); or, for a docs-, test-, CI- or skill-only change, an
   explicit "nothing user-visible changes" and why. "Nothing to check on a device" without
   test names is not enough for a change that alters user-visible behavior.

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
  The four reference skills (`tm-ios`, `tm-android`, `tm-kmp-shared`, `tm-testing`) are not
  protected (their `SKILL.md` files have ownerless lines in CODEOWNERS), so an agent may edit
  them in a task that calls for it; the reviewer judges that diff like any other, and the
  rule-change signal (`tm-pr-review` item 10) escalates any removed or rewritten rule line.
- An agent never merges a PR that touches a protected path. The human merges those. The one
  exception is a subtask PR into an epic branch whose plan `allowed_paths` cover the path
  (`tm-agent-loop`, "Merge conditions", condition 6); the epic PR into `main` is always the
  human's.
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
1. **Add.** Everything this PR leaves for later gets a record in `BOARD.md` in the **same**
   PR, in every run, whether or not the task came from the board: each follow-up and each
   drift you list under "Follow-ups (out of scope, not changed)" or "Drift found (not
   fixed)", including one only the human can do (a workflow file this token can't push). The
   human decides when it is done, not whether it is recorded. The PR description keeps those
   sections, and each bullet names its slug; a bullet without a slug breaks this rule. Every
   new record gets an `Order` and, only if it truly can't start before another record is done,
   an `After`.
2. **Delete.** When the task starts from a board record, delete that record in the PR that
   does the work, as its own commit (`chore(board): remove <slug>`).
   A PR closed unmerged never deletes it from `main`. If the work only partly resolves
   the record, narrow its Problem/Done when instead. If the record is obsolete, delete it
   and say why in the PR. The same commit removes the slug from every other record's
   `After` and from every board mention in the skills and docs, or `check-board.sh` fails.
   A mention in a historical plan under `docs/epics/` stays as written: the check only prints
   a notice for it.
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
2. The human checks the Tier 2 list (CI's `pr-reviewer` checks it too, `tm-pr-review`
   item 11): a test named for each user-visible behavior, or a valid reason for a human
   check, and does any human check it lists.
3. The human reviews the structure: does it follow the established pattern, respect module
   boundaries, and avoid duplicating something that should be shared?
4. Only then does the human merge into `main`, unless the PR meets the merge conditions in
   `tm-agent-loop`: then the agent merges it, and the human does step 2's human checks
   when testing the feature (the epic-level Tier 2). `tm-agent-loop` also has the
   after-merge cleanup and how to read the CI reviewer's verdict.

Review comments turn into new commits on the same branch, each through the gate again.
Answer them in the PR (see #35's comment summarising its second commit) rather than
silently force-pushing.

## Where enforcement and history differ from the rules

- **Branch protection enforces CI and code owner review.** As reported by the human on
  2026-10-18 (the machine token can't read the settings): `main` requires a PR and
  `enforce_admins` is on, so a direct push to `main` is rejected. Review from code owners is
  required, so a PR that touches an owned path in `.github/CODEOWNERS` can't merge without
  the code owner's approval, and stale approvals are dismissed when new commits are pushed.
  Branches must be up to date before merging. The required checks are
  `Android — Lint, Detekt, Tests, Build`, `iOS — all stages` (the `ios` aggregator job)
  and `Review — pr-reviewer`, so a PR can't merge with red CI or while it's behind `main`.
  "Require approvals" is off (approval count **0**), so a PR that touches no owned path
  needs no approval. #30–#37 were all merged with no review, before code owner review was
  required. The two CI checks were required before #38 merged.
- **The review check is required, but green is not approval.** `Review — pr-reviewer`
  (`.github/workflows/pr-review.yml`) is green for both `APPROVE` and `ESCALATE_TO_HUMAN`;
  the verdict is read from its annotation (`tm-agent-loop`, section 7).
  The annotation holds only the verdict; the report is the workflow artifact `pr-review-report`
  of that run (kept 7 days), which the agent downloads with `gh run download` after `CHANGES`
  or blocking findings (`tm-agent-loop`, section 7).
- **The protected-paths check runs in the gate and in CI** (the "Protected paths check"
  step of CI's `android` job).
- **"Automatically delete head branches" is enabled.** GitHub deletes a PR's remote branch
  when it merges; the local branch is the agent's to delete ("Before starting").
- **The gate is a Claude Code hook, not a git hook.** It is a `PreToolUse` hook, so it
  only gates pushes made from a Claude Code session. A push from a terminal skips it.
- **CI doesn't mirror the gate exactly.** CI's heavy steps run unless
  `scripts/classify-changes.sh` decides `light` (non-source changes only; pushes always run
  everything). Unlike the gate, CI's iOS jobs have no iOS path filter: on a non-`light` PR
  `ios-main` runs SwiftLint, the iOS build and the iOS simulator tests, and `ios-build-ui` and
  `ios-ui` build and run the UI tests, even when the gate skipped its iOS steps. For a diff in the
  UI scope the gate builds the `uitest` variant and runs ONE smoke UI test
  (`DetailsFailedDeleteUITests`); CI builds the variant once in `ios-build-ui` and runs ALL UI tests
  in `ios-ui`. So an `iosApp/` problem that already existed on `main` can make CI red on an
  unrelated Android-only PR. CI's `android` job runs on Ubuntu, where the iOS simulator tests are
  skipped; they run in `ios-main`, `domain`'s and `data`'s since #34, `shared`'s since S3 of
  `protected-paths-review-2`. The `ios` job is the aggregator that carries the required check
  name: it runs no build step and is green only when `ios-plan`, `ios-build-ui`, `ios-ui` and
  `ios-main` passed, or the three macOS jobs were skipped on a `light` decision.
- **CI's `xcodebuild` steps don't scrub the environment or filter the log; the gate does.**
  The gate removes secret-looking variables (`scripts/scrub-env.sh`) and filters the
  `export` dump out of the `xcodebuild` output (`scripts/filter-xcode-log.sh`). CI's
  `xcodebuild` steps do neither. Decided 2026-10-18 to leave CI as it is: the iOS jobs hold
  no secret (`ci.yml` references no `secrets.`, and the generated configuration file
  contains a placeholder key only), and GitHub masks real secrets in logs. If a secret is
  ever given to an iOS job, scrubbing and filtering become required first, with
  `set -o pipefail` in the step, because the default macOS `run:` shell has no pipefail.
- **CI only runs on push for `main` and `feature/epic/**`.** `ci.yml`'s push trigger doesn't
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
