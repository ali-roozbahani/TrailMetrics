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
all subtasks are in, the automated tests pass on the integrated result and the human's final
smoke check is done (Tier 2). The rest of this skill turns
those rules into concrete mechanics for this repo.

**The pattern has never been run here.** No epic branch exists in history. Everything
below comes from the retired workflow doc, `ci.yml`, the gate script, the push hook and `main`'s
protection as of 2026-09-28. It has not been tested on a real epic. The first epic should
check each assumption and report under "Drift found" where reality differs.

Everything per-PR is in **`tm-pr-workflow`** and is not repeated here: branch prefixes,
Tier 1 gate and hook, retry budget, the Tier 2 rule, commit/PR title format, the four
required PR description headings, and boundaries. It applies to every subtask unchanged.
This skill only states where an epic changes the base branch, the scope or the merge
conditions.

## Roles

- **Human**: approves the plan and every change to it, sets up branch protection, merges
  the epic PR into `main` (only the human), merges every subtask PR into the epic branch
  that an agent may not merge (`tm-agent-loop`, "Merge conditions"), and does the human
  part of Tier 2: the epic's final smoke check and any human check a PR lists with its
  reason (`tm-pr-workflow`, "Tier 2: what automated tests cannot show").
- **Orchestrator**: the Claude Code session the human is talking to. It drafts the plan,
  creates the epic branch and its draft PR after approval, spawns subtask agents wave by
  wave, checks that each subtask PR stayed inside its `allowed_paths`, and keeps the epic
  PR's status up to date. It writes no feature code itself.
- **Subtask agent**: one per subtask. It follows `tm-pr-workflow` plus the code skills
  for its paths, and opens one PR against the epic branch.

Inside its own work, a subtask agent (or the orchestrator, for the contract) may use the `explorer` and
`implementer` subagents like any run (`tm-agent-loop`, "Subagents"); they are tools of that agent, never
a subtask: they open no PR, and only the agent that started them integrates their commits. A subtask
agent started with `isolation: "worktree"` is a different thing from an implementer's worktree
(`scripts/subagent/worktree.sh`), which is created and removed by the agent that uses it.

The epic PR into `main` is the human's only, on the human's explicit command
(`docs/epics/agentic-dev-loop.md`, Decision 5). Subtask PRs into the epic branch follow
Decision 5: an agent may merge one only under the conditions in `tm-agent-loop` ("Merge
conditions"), where the subtask's plan `allowed_paths` replace "touches no protected path".
The human merges every other subtask PR.

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
  the protected paths stay off-limits unless the epic's human-approved scope names them.
  Which paths are protected is decided by `.github/CODEOWNERS` alone (`tm-pr-workflow`,
  "Boundaries"); check a path with `scripts/check-protected-paths.sh --files <path>...`
  instead of relying on a list here.
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
is a new directory this skill introduces. Whether it is protected is decided by
`.github/CODEOWNERS`; check with `scripts/check-protected-paths.sh --files`.) The file
records **decisions**. Live status (which PRs are open or
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

The plan file's format, and a worked example (personal records on History), are in
`plan-format.md`.

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

`main` today (as set by the human on 2026-10-18): PR required, required status checks
`Android — all stages`, `iOS — all stages`,
`Repo tooling — policy checks and script self-tests` and `Review — pr-reviewer` with
**strict** (up-to-date) on, 0 approvals, `enforce_admins` on, no force pushes, no deletions.
`pr-review.yml` has no branch filter, so `Review — pr-reviewer` runs for pull requests into
epic integration branches too.

**Recommendation: give epic branches the same protection as `main`, via one
repository ruleset that targets the pattern.** Don't set up classic protection per
branch. The reasons are in `epic-branch-protection.md`.

The human sets this up **once**, before the first epic. The orchestrator must not run
it. Suggested ruleset (same four checks, integration id 15368 = GitHub Actions, as on
`main`), and how to apply it: `epic-branch-protection.md`.

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
6. **After merge**: GitHub deletes the remote epic and subtask branches on merge
   ("Automatically delete head branches" is on). Local branches are the agent's
   after-merge cleanup (`tm-agent-loop`, "After-merge cleanup").

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

What was verified for the gate and hook in a linked worktree, and what was not yet, is in
`worktree-isolation.md`.

The caution that still applies to parallel worktrees:

- **Resource contention.** Every subtask runs the full gate. Its heavy steps (Gradle
  `detekt`, `lint`, `allTests test`, the Kover coverage report and `koverVerify`,
  `assembleDebug`, plus SwiftLint, the XCFramework build and `xcodebuild` once the diff
  touches `iosApp/` or the shared layer) run unless `scripts/classify-changes.sh` decides
  `light`; that script, not this skill, says which changes are `light`. Each worktree has its own build
  directories and Gradle daemon. Several gates at once on one machine compete for CPU,
  memory and the shared `~/.gradle` cache locks, and can be slower in total than running
  them one after another. Default to **at most two** concurrent subtasks, and fewer when
  more than one of them runs the iOS steps. The human can raise the limit.
  Since the heavy-run lock (`scripts/heavy-run.sh`, which the gate starts itself under) only one
  Gradle or `xcodebuild` run goes at a time on this machine, whoever starts it: the others wait and
  say who they wait for. Parallel subtasks therefore overlap their writing, not their gates, and a
  wait is neither a failure nor a gate attempt.
- **Untracked local files don't come along.** A new worktree has no `local.properties`
  (Android SDK path, `MAPS_API_KEY`) and no `iosApp/TrailMetrics/Secrets.xcconfig`, which
  the iOS build needs. Both are gitignored. The orchestrator copies them from the main
  checkout into each worktree before the subtask runs its gate. Never commit them.
  For an implementer's worktree, `scripts/subagent/worktree.sh create ... --ios --android` puts symbolic
  links to them in the worktree (never read, printed or copied by the script).
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

The template, with the Epic block: `subtask-prompt.md`.

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
  Under Tier 2, give the subtask's `tier2` line from the plan, with the tests' real names.
  The human may postpone a human check it lists to the epic-level Tier 2, which is their
  call.
- **Title**: `type(scope): summary` as usual. Subtask PRs squash-merge into the epic
  branch, so each subtask becomes one conventional commit there.
- **Board**: a subtask never edits `BOARD.md`, because parallel siblings would conflict
  on it. It lists drift and follow-ups in its PR description only, with
  `Board: no changes` (`tm-pr-workflow` → Board, rule 5).
- **Merge**: under Decision 5's conditions (`tm-agent-loop`, "Merge conditions", with the
  subtask's `allowed_paths` in place of "touches no protected path"). The agent posts its
  merge check (`tm-agent-loop`, "Auto-merge"); when a condition is "no", the human merges.

## Merging the epic into main

The orchestrator reports readiness. The human merges only when all of these hold:

1. Every subtask in the plan has its PR merged into the epic branch, or was dropped by a
   plan change the human approved. None is still open.
2. The epic branch includes the latest `main` (strict protection on `main` enforces this;
   sync as in Lifecycle step 4).
3. CI is green on the epic PR for every required check, on its current head.
4. **The final board PR is merged into the epic branch, and only then** has the
   orchestrator marked the epic PR ready for review (`gh pr ready <n>`). The final board
   PR is the one board-only PR an epic uses (`tm-pr-workflow` → Board, rule 5). The
   orchestrator opens it into the epic branch after every subtask is merged. It is not a
   plan subtask. It adds `BOARD.md` records for the drift and follow-ups the subtasks
   reported, and deletes the epic's own record if the epic started from one. The
   orchestrator has also filled in the epic PR's description: What changed per subtask
   (with PR links), Skills/docs followed (the union), Tier 1 (the CI result on the epic
   head; no separate local gate is needed, since nothing new is pushed at this point),
   Tier 2 (the plan's epic-level list), any Assumptions and Follow-ups from the subtasks,
   and a `Board:` line listing the records the final board PR added and removed. An epic
   record on the board always points to its plan under `docs/epics/`.
5. The epic-level Tier 2 is done **on the integrated epic branch head**: the automated tests
   that cover the epic's end-to-end behavior on both platforms pass there where such a test
   can exist (condition 3), the human has done the final smoke check and every human check
   listed with its reason, and has reviewed the full diff against `main`.

**Merge method (recommendation; the human decides): "Create a merge commit"**, not
squash. Each subtask is already one conventional commit on the epic branch (`... (#N)`).
A merge commit keeps them in `main`'s history and keeps each one revertible. Squash would
collapse the epic into one commit and lose that. The repo allows all three methods. The
epic PR title is still a valid `type(scope): summary`, because it appears in the merge
commit.

## Where this skill made calls the retired workflow doc didn't

Recorded so the first real epic can confirm or correct them: `decisions-history.md`.
