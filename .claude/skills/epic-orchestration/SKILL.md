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

## Topic files

What applies at the start of every epic stays in this file: the roles, deciding epic or single task, committing the
plan, the `allowed_paths` conventions, the plan and its approval, the integration branch (naming, protection,
lifecycle). The three files below hold what happens once the plan is approved. Read each when the epic reaches its
topic, not before. Section headings are unchanged, so a reference to `epic-orchestration`, "<heading>", is found in
this file or in the file named here. The detail files that already existed (`plan-format.md`, `subtask-prompt.md`,
`worktree-isolation.md`, `epic-branch-protection.md`, `decisions-history.md`) are named where this file points to them.

| File | Read it when |
|---|---|
| `spawning-subtasks.md` ("Spawning subtask agents", "Waves", "Isolation", "What a subtask agent is told") | the plan is approved and the first wave is about to start: which subtasks are ready, disjointness, worktrees, the task prompt |
| `subtask-prs.md` ("Subtask PRs") | a subtask agent has finished and its PR against the epic branch is opened, reviewed or merged |
| `merging-the-epic.md` ("Merging the epic into main") | every subtask is merged into the epic branch and the epic PR into `main` is prepared |


## Roles

- **Human**: approves the plan and every change to it, sets up branch protection, merges
  the epic PR into `main` (only the human), merges every subtask PR into the epic branch
  that an agent may not merge (`tm-agent-loop`, "Merge conditions", `merge.md`), and does the human
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
conditions", `merge.md`), where the subtask's plan `allowed_paths` replace "touches no protected path".
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
3. **Waves**: see "Waves" (`spawning-subtasks.md`).
4. **Keeping up with `main`**: if `main` moves while the epic is open, the epic branch
   must include it before it can merge (`main` is strict). Sync through a PR, never a
   direct push: a `chore/<epic-slug>-sync-main` branch off the epic branch, then
   `git merge origin/main` (no rebase, which would rewrite commits that subtask branches
   are based on), gate, push, and a PR against the epic branch. Conflicts are resolved
   there, within the scope that the conflicting files' owners had. Sync between waves,
   not during one.
5. **Finish**: see "Merging the epic into main" (`merging-the-epic.md`).
6. **After merge**: GitHub deletes the remote epic and subtask branches on merge
   ("Automatically delete head branches" is on). Local branches are the agent's
   after-merge cleanup (`tm-agent-loop`, "After-merge cleanup", `merge.md`).

**Abandoning an epic**: close the draft epic PR and delete the branch. Nothing reached
`main`, which is the point of having an integration branch.

## Where this skill made calls the retired workflow doc didn't

Recorded so the first real epic can confirm or correct them: `decisions-history.md`.
