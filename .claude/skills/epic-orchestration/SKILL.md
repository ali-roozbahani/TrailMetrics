---
name: epic-orchestration
description: Use when a TrailMetrics change is big enough to split across layers or platforms (e.g. a shared-layer change plus separate Android and iOS UI work) and should run as a multi-agent epic. Covers deciding epic vs. single task, writing the human-reviewed plan (subtasks, depends_on, allowed_paths, acceptance criteria), allowed_paths conventions for this repo's modules, integration branch naming, lifecycle and protection, spawning and scoping parallel subtask agents, subtask PRs against the epic branch, and the conditions for merging the epic into main. Not for per-PR mechanics (see tm-pr-workflow) or how to write the code (see tm-kmp-shared, tm-android, tm-ios, tm-testing).
---

# TrailMetrics multi-agent epics

This skill is the source of truth for multi-agent epics (it replaced the "Multi-agent epics"
section of the retired `coding_agent_workflow.md`). It rests on four rules: a human-reviewed
plan comes first; subtasks whose `allowed_paths` don't overlap and whose `depends_on` are
all met may run in parallel, each on its own branch and PR against the epic's integration
branch; every standing rule applies per subtask; the human merges the epic into `main` once
all subtasks are in and Tier 2 passes on the integrated result. The rest of this skill turns
those rules into concrete mechanics for this repo.

**The pattern has never been run here.** No epic branch exists in history. Everything
below comes from the retired workflow doc, `ci.yml`, the gate script, the push hook and `main`'s
protection as of 2026-09-28. It has not been tested on a real epic. The first epic should
check each assumption and report under "Drift found" where reality differs.

Everything per-PR is in **`tm-pr-workflow`** and is not repeated here: branch prefixes,
Tier 1 gate and hook, retry budget, Tier 2 handoff, commit/PR title format, the four
required PR description headings, and boundaries. It applies to every subtask unchanged.
This skill only states where an epic changes the base branch, the scope or the merge
conditions.

## Roles

- **Human**: approves the plan and every change to it, sets up branch protection, merges
  every PR (subtask → epic branch and epic → `main`), and does Tier 2.
- **Orchestrator**: the Claude Code session the human is talking to. It drafts the plan,
  creates the epic branch and its draft PR after approval, spawns subtask agents wave by
  wave, checks that each subtask PR stayed inside its `allowed_paths`, and keeps the epic
  PR's status up to date. It writes no feature code itself.
- **Subtask agent**: one per subtask. It follows `tm-pr-workflow` plus the code skills
  for its paths, and opens one PR against the epic branch.

No agent merges any PR, into `main` or into the epic branch. The retired workflow doc only
forbids merging into `main`. This skill applies the same rule to the epic branch
(conservative reading: the human keeps every merge decision).

## Epic or single task?

Use an epic only when **all** of these hold:

- The change spans at least two of: the shared layer (`domain`/`data`/`core`/`shared`),
  Android UI (`androidApp/`), iOS UI (`iosApp/`).
- After a first contract subtask (models, use case, Koin binding, `KoinHelper` getter),
  the rest splits into subtasks with disjoint `allowed_paths` that can run in parallel.
  The usual shape is Android UI ∥ iOS UI.
- `main` shouldn't hold the half-built state. Example: a shared API with no UI on one
  platform, or a UI on one platform only.

Use a single task (or a chain of ordinary PRs against `main`) when:

- Only one platform's UI changes, even if it needs a new use case. Shared plus one UI is
  strictly sequential, so an epic's branch and waves only add overhead.
- It's a bugfix, a refactor inside one module, or a docs/CI/lint/gate/skills change.
- The subtasks would all need the same hotspot files (see below). They'd have to run
  one after another anyway.
- You can't write acceptance criteria for each subtask before any code exists. The plan
  isn't ready yet. Investigate first as a separate task.

### Committing the plan

What happens to the plan file depends on the answer above:

- **Epic:** the plan is always committed, to `docs/epics/<epic-slug>.md`, as the first
  commit on the integration branch. See "The plan" and Lifecycle step 1.
- **Single task:** the plan is **not** committed by default. Most single-task plans are
  small and throwaway, and committing every one would fill `docs/epics/` with plans
  nobody reads again.
- **Single task, kept on request:** the human may decide a particular plan is worth
  keeping as a reference for future planning, for example because it's substantial or
  likely to set a pattern other tasks will copy. Then it's committed to
  `docs/epics/<slug>.md` with nothing else required: there's no integration branch, so
  it's a normal commit on whichever branch is convenient. It can ride along on an
  unrelated open PR (as `mvi-presentation-migration.md` did in #59) or go out on its own
  `chore/` branch and PR.

Keeping a single-task plan is the human's call. When a plan looks worth keeping, the
agent says so ("this plan could be worth keeping as a reference — want it committed?")
but never commits it unprompted.

## allowed_paths conventions for this repo

`allowed_paths` is the list of files a subtask may **write**. Agents may read anything.

- Globs are relative to the repo root: `**` spans directories, `*` stays within one path
  segment. Use the narrowest glob that still covers the work. Prefer a directory glob
  when the subtask owns the whole directory, such as a feature module.
- A subtask's tests go in its own paths: `domain/src/commonTest/**` alongside the
  `domain/src/commonMain/**` files it changes, `androidApp/feature-x/src/test/**` alongside
  `feature-x`. Tests are never a separate parallel subtask (`tm-testing` owns how to write
  them).
- `allowed_paths` never overrides a boundary. Module boundaries from `tm-kmp-shared` and
  the protected files from `tm-pr-workflow` (docs/architecture, CI, lint config, the gate,
  the hook, skills, `CLAUDE.md`) stay off-limits unless the epic's human-approved scope
  names them.
- **Disjoint means no file could match two concurrent subtasks' globs.** Check it on
  globs, not only on the files you expect: `androidApp/**` and
  `androidApp/feature-history/**` overlap.

### Natural seams (safe to split along)

| Area | Typical glob | Notes |
|---|---|---|
| Android feature UI | `androidApp/feature-<name>/**` | One module per feature. Includes its Koin UI module (`di/<Name>UiModule.kt`) and tests. |
| iOS feature UI | `iosApp/Packages/<Name>/**` | One SPM package per feature. Adding files to an existing package doesn't touch `project.pbxproj`. Exclude `.build/` (build output, not source). |
| Android design system | `androidApp/core-ui/**` | Shared by all Android features. At most one subtask per wave. |
| iOS design system | `iosApp/Packages/DesignSystem/**` | Same rule. |

### Hotspots: one owner per wave

Many kinds of change route through these files. Give each to **at most one subtask at a
time**, usually the contract subtask or a final wiring subtask:

- `domain/**`, `data/**`, `core/**`, `shared/**`. Keep shared-layer work in **one** contract
  subtask that runs first. Split it (domain first, then data/shared) only if it's large,
  and then sequentially. Specific hot files: `data/src/commonMain/**/di/*.kt` (Koin
  modules), `shared/src/iosMain/**/di/KoinHelper.kt`, `shared/src/commonMain/**/di/KoinInit.kt`,
  `core/**` (`AppRoute`, `RouteUiError`).
- `androidApp/app/**`: `TrailMetricsApplication.kt` (Koin start), `MainActivity.kt` and
  `navigation/` (routes, bottom bar).
- `iosApp/TrailMetrics/**` (`ContentView.swift` routing, `TrailMetricsApp.swift`) and
  `iosApp/TrailMetrics.xcodeproj/**`. `project.pbxproj` changes whenever a package or an
  app-target file is added, and it merges badly. Never give it to two subtasks at once.
- `settings.gradle.kts`, any `build.gradle.kts`, `gradle/libs.versions.toml`,
  `Package.swift`. These change only when adding a module, and dependencies need the
  task to name them (`tm-pr-workflow` → Boundaries).

Because every subtask that touches the shared layer also triggers the iOS gate and needs an
XCFramework rebuild, UI subtasks that need a new shared API always `depends_on` the
contract subtask. They never run alongside it with a stubbed API.

## The plan

An epic's plan is a committed file, `docs/epics/<epic-slug>.md`. It is the first commit
on the epic branch, so the epic branch differs from `main` and its draft PR can be opened. The
plan is also the record in history of how the epic was split. (Assumption: `docs/epics/`
is a new directory this skill introduces. It sits outside the protected
`docs/architecture/`.) The file records **decisions**. Live status (which PRs are open or
merged) goes in the epic PR description, so that subtask PRs never edit the plan file and
never conflict on it.

### Workflow

1. The orchestrator drafts the plan in chat or a scratch file and shows it to the human.
   It doesn't create a branch or spawn anything yet.
2. The human reviews and approves it (or edits it). **No subtask starts before this.**
3. The orchestrator creates the epic branch, commits the plan, runs the gate and pushes
   (see Lifecycle), then opens the draft epic PR.
4. Any later change to `depends_on`, `allowed_paths` or acceptance criteria needs the
   human to approve it again, and gets its own `chore(epic)` commit to the plan file on
   the epic branch, through a PR like everything else.

### Format

````markdown
# Epic: <title>

- **Slug:** <epic-slug>
- **Integration branch:** feature/epic/<epic-slug>
- **Goal:** <one paragraph: what the user can do when this lands>
- **Out of scope:** <explicit list>
- **Approved by:** <human> on <YYYY-MM-DD>

## Subtasks

```yaml
- id: S1
  title: <imperative summary>
  branch: <feature|bugfix|chore>/<epic-slug>-<subtask-slug>
  skills: [tm-kmp-shared, tm-testing]
  depends_on: []
  allowed_paths:
    - <glob>
  acceptance:
    - <checkable statement>
  tier2: <what the human checks on a device, or "none — shared only">
```

## Waves

- Wave 1: S1
- Wave 2: S2 ∥ S3   (disjoint: <one line on why>)

## Epic-level Tier 2 (on the integrated branch before merge to main)

- <end-to-end checks across both platforms>
````

### Worked example: personal records on History

The feature: History on both platforms shows the user's longest distance and fastest
average pace across saved activities.

````markdown
# Epic: Personal records on History

- **Slug:** personal-records
- **Integration branch:** feature/epic/personal-records
- **Goal:** Both History screens show a "Personal records" section (longest distance,
  fastest average pace) computed once in `domain` from `ActivityHistoryRepository`.
- **Out of scope:** persisting records;
  records per `ActivityType`; any change to Tracking or Route.
- **Approved by:** <human> on 2026-10-01

## Subtasks

```yaml
- id: S1
  title: Add GetPersonalRecordsUseCase and expose it to both platforms
  branch: feature/personal-records-shared
  skills: [tm-kmp-shared, tm-testing]
  depends_on: []
  allowed_paths:
    - domain/src/commonMain/**/model/PersonalRecords.kt
    - domain/src/commonMain/**/usecase/GetPersonalRecordsUseCase.kt
    - domain/src/commonTest/**/usecase/GetPersonalRecordsUseCaseTest.kt
    - data/src/commonMain/**/di/UseCaseModule.kt
    - shared/src/iosMain/**/di/KoinHelper.kt
  acceptance:
    - PersonalRecords is a pure domain model; GetPersonalRecordsUseCase reads
      ActivityHistoryRepository and returns null fields when history is empty.
    - kotlin.test cases cover empty history, one activity, ties, and zero-distance
      activities, using the existing FakeActivityHistoryRepository.
    - Bound in useCaseModule; KoinHelper has a concrete getPersonalRecordsUseCase().
  tier2: none — no UI yet

- id: S2
  title: Show personal records on Android History
  branch: feature/personal-records-android
  skills: [tm-android, tm-testing]
  depends_on: [S1]
  allowed_paths:
    - androidApp/feature-history/**
  acceptance:
    - HistoryScreen shows the section above the list; hidden when there is no history.
    - The records are new HistoryState fields only; HistoryViewModel keeps its MVI
      shape (no new public method besides onAction).
    - HistoryUiModule gets the use case via Koin; ViewModel test covers both states.
  tier2: Android emulator: empty history → no section; save two activities → values match.

- id: S3
  title: Show personal records on iOS History
  branch: feature/personal-records-ios
  skills: [tm-ios]
  depends_on: [S1]
  allowed_paths:
    - iosApp/Packages/History/Sources/**
    - iosApp/Packages/History/Tests/**
  acceptance:
    - HistoryViewModel resolves the use case via a KoinHelper default-parameter init.
    - HistoryView shows the same section with the same empty-state rule as Android.
  tier2: iOS simulator: same two checks as S2.
```

## Waves

- Wave 1: S1
- Wave 2: S2 ∥ S3   (disjoint: androidApp/feature-history/** vs iosApp/Packages/History/**;
  neither touches app/, TrailMetrics/, the xcodeproj or the shared layer)

## Epic-level Tier 2

- Same data on both platforms shows identical records and formatting.
- Deleting the record-holding activity updates the section on both platforms.
````

Notes on the example: S2 and S3 don't need `androidApp/app/**` or `iosApp/TrailMetrics/**`
because History is already routed on both platforms. If a feature needed a new screen
route, that wiring would be a separate subtask after S2/S3, or it would go into exactly
one of them.

## Integration branch

### Naming

**`feature/epic/<epic-slug>`**. Each part of the name is there for a reason:

- **`feature/` prefix, so CI runs.** `ci.yml` triggers `pull_request` only for base
  branches matching `main` or `feature/**`. A subtask PR against `epic/<slug>` or
  `chore/epic-<slug>` would get **no CI at all**. If the branch also required status
  checks, its PRs could never be merged.
- **`epic/` segment, so branch protection can target epic branches without catching
  subtask branches.** A GitHub ruleset pattern `feature/epic/*` matches the integration
  branch. It doesn't match subtask branches named `feature/<epic-slug>-<subtask>`.
  (`feature/epic-*` would match both, and would then require PRs to push to a subtask
  branch.)
- Subtask branches can't live *under* the epic branch (`feature/epic/<slug>/s1`), because
  git can't have a ref and a directory with the same name. So they're siblings:
  `<feature|bugfix|chore>/<epic-slug>-<subtask-slug>`.
- No ref named exactly `feature/epic` may ever exist, or the prefix becomes unusable.

### Protection

`main` today (checked 2026-09-28): PR required, required status checks
`Android — Lint, Detekt, Tests, Build` and `iOS — SwiftLint, Build` with **strict**
(up-to-date) on, 0 approvals, `enforce_admins` on, no force pushes, no deletions.

**Recommendation: give epic branches the same protection as `main`, via one
repository ruleset that targets the pattern.** Don't set up classic protection per
branch. The reasons:

- Subtask PRs merge into the epic branch, not `main`. Without required checks, a red
  subtask can land there, and the problem only shows up when the epic's PR to `main`
  fails. By then it's mixed in with every other subtask.
- **Strict** matters most here. Parallel subtasks (S2 ∥ S3) each go green against the
  epic branch as it was when they started. Strict forces the second one to merge in the
  first and go green again before it can merge. That's the only point where the
  *combination* gets tested before the final PR.
- The branch is per-epic, but a ruleset on `refs/heads/feature/epic/*` covers every
  future epic branch the moment it's created. There's nothing to remember per epic, and
  no window where the branch is unprotected. The repo is public, so rulesets are
  available.
- Both CI jobs run on every PR (no path filters), so requiring both checks can't leave a
  PR stuck waiting for a check that never runs.

The human sets this up **once**, before the first epic. The orchestrator must not run
it. Suggested ruleset (same checks, integration id 15368 = GitHub Actions, as on `main`):

```json
{
  "name": "Epic integration branches",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/feature/epic/*"], "exclude": [] } },
  "rules": [
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false, "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": true,
        "required_status_checks": [
          { "context": "Android — Lint, Detekt, Tests, Build", "integration_id": 15368 },
          { "context": "iOS — SwiftLint, Build", "integration_id": 15368 } ] } },
    { "type": "non_fast_forward" }
  ]
}
```

`do_not_enforce_on_create: true` is explicit because GitHub defaults it to `false`, which
rejects creating the branch unless its base commit already has both checks green.

Apply it with `gh api -X POST repos/ali-roozbahani/TrailMetrics/rulesets --input <file>`,
or through Settings → Rules. There are no bypass actors, which matches `enforce_admins` on
`main`. It deliberately has no `deletion` rule, so the human can delete the branch after
the epic lands. It has no `creation` rule, so the branch can be created by a plain push.

**Pre-flight check for the orchestrator:** before creating the epic branch, run
`gh api repos/ali-roozbahani/TrailMetrics/rulesets`. If no active ruleset covers
`refs/heads/feature/epic/*`, stop and ask the human whether to set it up first or proceed
unprotected. Don't create the ruleset yourself.

### Lifecycle

1. **Create** (orchestrator, after plan approval and pre-flight):
   `git fetch origin && git switch -c feature/epic/<slug> origin/main`, commit the plan as
   `chore(epic): add <slug> plan`, run `scripts/pre-push-check.sh`, then push. The plan
   is the one commit pushed straight to the epic branch: the `pull_request` rule
   doesn't apply to creating the branch. Every later change arrives through a PR.
2. **Open the epic PR as a draft**, straight away:
   `gh pr create --draft --base main --head feature/epic/<slug>`, titled
   `feat(<scope>): <epic summary>`. The body contains the plan link, a status table (one
   row per subtask: branch, PR #, state) and the four `tm-pr-workflow` headings, filled
   in at the end. The orchestrator updates the status table as subtask PRs open and merge.
3. **Waves**: see below.
4. **Keeping up with `main`**: if `main` moves while the epic is open, the epic branch
   must include it before it can merge (`main` is strict). Sync through a PR, never a
   direct push: a `chore/<epic-slug>-sync-main` branch off the epic branch, then
   `git merge origin/main` (no rebase, which would rewrite commits that subtask branches
   are based on), gate, push, and a PR against the epic branch. Conflicts are resolved
   there, within the scope that the conflicting files' owners had. Sync between waves,
   not during one.
5. **Finish**: see "Merging the epic into main".
6. **After merge**: the human deletes `feature/epic/<slug>` and the subtask branches
   (`delete_branch_on_merge` is off in this repo).

**Abandoning an epic**: close the draft epic PR and delete the branch. Nothing reached
`main`, which is the point of having an integration branch.

## Spawning subtask agents

### Waves

A subtask is **ready** when every id in its `depends_on` has its PR **merged into the epic
branch**. An open or approved PR doesn't count: the dependent subtask must branch from
code that is already on the epic branch. The orchestrator spawns a wave, meaning all
ready subtasks whose `allowed_paths` are pairwise disjoint. It then waits for the human to
merge that wave's PRs before it spawns the next one.

Before each wave, check disjointness mechanically, not by eye. For every pair in the
wave, list which tracked files match both glob sets. If any file matches both, the
subtasks can't run in parallel. Tracked files alone can't catch two *new* files at the
same path, so also compare the new file paths the plan names.

### Isolation (read before running two subtasks at once)

Parallel subtasks need separate working trees: two agents on one checkout would switch
branches under each other. The tool for this is the Agent tool with
`isolation: "worktree"`, and **the gate and push hook work in a linked worktree** since #40
(`fix(hooks): resolve the gate pass marker per worktree`):

- `scripts/pre-push-check.sh` writes its pass marker at
  `git rev-parse --path-format=absolute --git-path .pre-push-check-passed`. That is
  `.git/` in the main checkout and `.git/worktrees/<name>/` in a linked worktree. If the
  marker can't be written, the gate fails instead of exiting 0.
- `scripts/claude-hooks/block-git-push.sh` resolves the checkout from the `cwd` in its
  hook input (falling back to its own checkout), then finds that checkout's marker the
  same way, and compares it with that checkout's last commit.

Verified on 2026-09-29 against `main` at `09a86a8`:
- In a throwaway linked worktree, the full gate passed (exit 0) and wrote the marker under
  `.git/worktrees/<name>/`.
- The hook, fed a push command with that worktree as `cwd`, allowed it (exit 0).
- With a fresh worktree that had no marker as `cwd`, it blocked (exit 2).

Not yet verified: a real push from an Agent-tool worktree session, i.e. that the hook
input's `cwd` there is the worktree. The first epic that runs parallel subtasks should
confirm it and report under "Drift found" if it isn't.

The caution that still applies to parallel worktrees:

- **Resource contention.** Every subtask runs the full gate: Gradle `detekt`, `lint`,
  `allTests test`, the Kover coverage report, `assembleDebug`, plus SwiftLint, the XCFramework build and `xcodebuild`
  once the diff touches `iosApp/` or the shared layer. Each worktree has its own build
  directories and Gradle daemon. Several gates at once on one machine compete for CPU,
  memory and the shared `~/.gradle` cache locks, and can be slower in total than running
  them one after another. Default to **at most two** concurrent subtasks, and fewer when
  more than one of them runs the iOS steps. The human can raise the limit.
- **Untracked local files don't come along.** A new worktree has no `local.properties`
  (Android SDK path, `MAPS_API_KEY`) and no `iosApp/TrailMetrics/Secrets.xcconfig`, which
  the iOS build needs. Both are gitignored. The orchestrator copies them from the main
  checkout into each worktree before the subtask runs its gate. Never commit them.
- **Sequential in the main checkout is still fine.** It's the right choice when the
  machine can't take concurrent builds or a wave has only one subtask. The ordering,
  scoping and PR-per-subtask rules are the same either way.
- Each worktree is cleaned up after its subtask's PR is opened. The branch lives on in
  the remote.

Never work around the hook (for example by touching the marker by hand, or pushing from a
command the hook's pattern doesn't match). That's a gate bypass, not a fix.

### What a subtask agent is told

The subtask prompt is the standard task prompt template from `tm-pr-workflow` with an
**Epic** block added. Write the block into the prompt itself: a spawned agent starts with
no memory of the planning conversation.

```
Task: <subtask title>

Epic:
- Epic plan: docs/epics/<epic-slug>.md on origin/feature/epic/<epic-slug> (read it; subtask <id>)
- Base branch: feature/epic/<epic-slug>. Branch from origin/feature/epic/<epic-slug>,
  and open the PR with --base feature/epic/<epic-slug>, NOT main.
- depends_on: <ids>, already merged into the base branch: <what they added that you use>
- allowed_paths (the only files you may create, modify or delete):
    <globs, verbatim from the plan>
- Parallel sibling(s): <ids + their allowed_paths>. Do not touch those paths.
- If the task can't be done inside allowed_paths, stop and report which file and why.
  Do not edit it. The plan changes only with human approval.

Context:
- Skills to load: tm-pr-workflow, <code skills from the plan>
- Reference implementation: <path>
- <anything else>

Scope:
- Acceptance criteria: <verbatim from the plan>
- Out of scope: <epic's out-of-scope list + anything subtask-specific>

Branch: <branch from the plan>
```

Don't pass `model` overrides or extra tools beyond the defaults unless the human asks.

## Subtask PRs

Everything in `tm-pr-workflow` applies. Only these parts change:

- **Base**: `git switch -c <branch> origin/feature/epic/<slug>` (after `git fetch origin`),
  and `gh pr create --base feature/epic/<slug>`. A subtask PR against `main` is wrong:
  close it and reopen it against the epic branch.
- **Scope check before push**: `git diff --name-only origin/feature/epic/<slug>...HEAD`
  must list only files matching `allowed_paths`. Put the output in the PR under
  "What changed". The orchestrator re-checks it when the PR opens.
- **Gate scope**: `pre-push-check.sh` diffs against the merge-base with `origin/main`, not
  the epic branch. Once the contract subtask is merged, **every** later subtask runs
  the iOS steps, including an Android-only one, because the epic's shared changes are in
  its diff. That's expected: it builds iOS against the integrated shared layer. Report it
  in Tier 1 rather than calling it spurious.
- **Out of date with the epic branch** (a sibling merged first, and strict blocks the
  merge): `git merge origin/feature/epic/<slug>` into the subtask branch (not rebase plus
  force-push), re-run the gate, push, and comment on the PR. That's a new commit, not a
  retry-budget attempt. A merge conflict means two subtasks' `allowed_paths` overlapped.
  Stop and report it as a plan defect.
- **PR description**: the four `tm-pr-workflow` headings, plus a first line
  `Epic: <slug> · Subtask <id> · depends_on: <ids>` linking the plan and the epic PR.
  Under Tier 2, give the subtask's `tier2` line from the plan. The human may postpone
  device checks to the epic-level Tier 2, which is their call.
- **Title**: `type(scope): summary` as usual. Subtask PRs squash-merge into the epic
  branch, so each subtask becomes one conventional commit there.
- **Merge**: by the human only, once CI is green on both checks.

## Merging the epic into main

The orchestrator reports readiness. The human merges only when all of these hold:

1. Every subtask in the plan has its PR merged into the epic branch, or was dropped by a
   plan change the human approved. None is still open.
2. The epic branch includes the latest `main` (strict protection on `main` enforces this;
   sync as in Lifecycle step 4).
3. CI is green on the epic PR for both required checks, on its current head.
4. The orchestrator has marked the epic PR ready for review
   (`gh pr ready <n>`), and filled in its description: What changed per subtask (with PR
   links), Skills/docs followed (the union), Tier 1 (the CI result on the epic head; no
   separate local gate is needed, since nothing new is pushed at this point), Tier 2 (the
   plan's epic-level list), plus any Assumptions and Follow-ups from the subtasks.
5. The human has done Tier 2 **on the integrated epic branch head**, including the
   epic-level cross-platform checks, and reviewed the full diff against `main`.

**Merge method (recommendation; the human decides): "Create a merge commit"**, not
squash. Each subtask is already one conventional commit on the epic branch (`... (#N)`).
A merge commit keeps them in `main`'s history and keeps each one revertible. Squash would
collapse the epic into one commit and lose that. The repo allows all three methods. The
epic PR title is still a valid `type(scope): summary`, because it appears in the merge
commit.

## Where this skill made calls the retired workflow doc didn't

Recorded so the first real epic can confirm or correct them:

- Branch naming `feature/epic/<slug>` and sibling subtask branches: the retired workflow doc
  named no convention. `ci.yml`'s `feature/**` trigger forces the prefix.
- Protection for epic branches through a single ruleset: the retired workflow doc
  predated required checks on `main` and said nothing about epic branches.
- No agent merges into the epic branch: the retired workflow doc only forbade merging into
  `main`.
- The plan lives in `docs/epics/<slug>.md`: the retired workflow doc said the plan must be
  reviewed, not where it goes.
- "Ready" means the dependency is merged, not just its PR opened.
- Merge commit for epic → `main`, where every other PR is squash-merged.
- Parallel subtasks run in linked worktrees, which the gate and hook support since #40
  (verified 2026-09-29, see "Isolation"), with a default cap of two concurrent subtasks
  to limit build contention. An earlier version of this skill said the gate/hook
  probably broke in worktrees and made sequential the default; that was true before #40.
