---
name: epic-orchestration
description: Use when a TrailMetrics change is big enough to split across layers or platforms (e.g. a shared-layer change plus separate Android and iOS UI work) and should run as a multi-agent epic, or an approved epic the owner starts with "run the epic <slug>". Covers deciding epic vs. single task, writing the human-reviewed plan (subtasks, depends_on, allowed_paths, acceptance criteria), allowed_paths conventions for this repo's modules, integration branch naming, lifecycle and protection, spawning and scoping parallel subtask agents, subtask PRs against the epic branch, and the conditions for merging the epic into main, and the whole run of an approved epic from one command (running-an-epic.md). Not for per-PR mechanics (see tm-pr-workflow) or how to write the code (see tm-kmp-shared, tm-android, tm-ios, tm-testing).
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
protection as of 2026-09-28, and was read again against the first epic's plan on 2026-11-19
(`running-an-epic.md` is the result). It has not been tested on a real epic. The first epic should
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
| `running-an-epic.md` ("The command", the steps 1 to 4, "The queue and the epic", "What the owner does") | the owner says "run the epic `<slug>`", or a run of an epic resumes: the whole procedure from the checks to the epic PR that is ready |
| `spawning-subtasks.md` ("Spawning subtask agents", "Waves", "Workers", "Isolation", "What a subtask worker is told") | the first wave is about to start: which subtasks are ready, disjointness, the worktrees, the task file |
| `subtask-prs.md` ("Subtask PRs") | a worker has finished and its PR against the epic branch is opened, reviewed or merged |
| `merging-the-epic.md` ("Merging the epic into main") | every subtask is merged into the epic branch and the epic PR into `main` is prepared |


## The command

The owner starts an approved epic with one sentence: "run the epic `<slug>`". The orchestrator then runs the whole epic
by `running-an-epic.md` and asks for nothing else: it checks what has to be checked, creates the epic branch and its
draft PR, runs the waves in the order the plan's `depends_on` gives, keeps the epic PR's status table current, merges
the subtask PRs it may merge, stops only for what only the human can do, and ends with the epic PR ready and a report.
The same sentence resumes a run that stopped. Without that command, an epic whose plan is approved stays as it is
(`tm-agent-loop`, section 1).

## Roles

- **Human**: approves the plan (by merging the PR that adds it to `main`) and every change to
  it, sets up branch protection, says "run the epic `<slug>`", merges the epic PR into
  `main` (only the human), merges every subtask PR into the epic branch that an agent may not
  merge (`tm-agent-loop`, "Merge conditions", `merge.md`) and the epic's final board PR (it
  edits the plan's `Status`, a protected path), and does the human part of Tier 2: the epic's
  final smoke check and any human check a PR lists with its reason (`tm-pr-workflow`, "Tier 2:
  what automated tests cannot show").
- **Orchestrator**: the Claude Code session the human is talking to. It drafts the plan,
  and on the command "run the epic `<slug>`" it creates the epic branch and its draft PR,
  starts a worker for each subtask wave by wave, integrates every worker's commits (the
  local review, the gate, the push, the PR, CI, the merge when it may merge), checks that
  each subtask PR stayed inside its `allowed_paths`, and keeps the epic PR's status table
  up to date. It writes no feature code itself.
- **Subtask worker**: one `implementer` per subtask (`tm-agent-loop`, "Subagents"), in its own
  worktree made by `scripts/subagent/worktree.sh`, with the subtask's `allowed_paths` as its
  allowed paths. It writes code and commits to the worktree's branch, and nothing else: it
  opens no PR, runs no gate and starts no subagent. Why the orchestrator integrates and no
  worker opens its own PR: the push hook refuses a push without a recorded local review of
  that commit, the reviewer is a subagent, and nothing below the orchestrator spawns
  (`tm-agent-loop`, "Subagents", "Nesting"); `tm-agent-loop`, "Never", forbids a subagent
  to push, open, review or merge a PR. An epic is still one PR per subtask, with one review
  and one gate run, as any task.

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

- **Epic:** the plan is always committed, to `docs/epics/<epic-slug>.md`. It reaches `main`
  first, through a PR the human merges (`/docs/epics/` is a protected path), and that merge is
  the plan's approval; the epic branch is created after it. See "The plan" and Lifecycle step 1.
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

An epic's plan is a committed file, `docs/epics/<epic-slug>.md`. It is on `main` before
the epic branch exists (the PR that adds it is the human's to merge; its merge, with the
"Approved by" line filled, is the approval). The epic branch's first commit then changes the
plan's `Status` line to `running`, so the branch differs from `main` and its draft PR can be
opened. The plan is also the record in history of how the epic was split. (Assumption: `docs/epics/`
is a new directory this skill introduces. Whether it is protected is decided by
`.github/CODEOWNERS`; check with `scripts/check-protected-paths.sh --files`.) The file
records **decisions**. Live status (which PRs are open or
merged) goes in the epic PR description, so that subtask PRs never edit the plan file and
never conflict on it.

### Workflow

1. The orchestrator drafts the plan in chat or a scratch file and shows it to the human.
   It doesn't create a branch or spawn anything yet.
2. The human reviews and approves it (or edits it). **No subtask starts before this.**
3. The plan is merged into `main` by the human. On the command "run the epic `<slug>`" the
   orchestrator creates the epic branch, commits the `Status` line, runs the gate and pushes
   (see Lifecycle), then opens the draft epic PR (`running-an-epic.md`).
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

**Pre-flight check for the orchestrator:** before creating the epic branch, run the check
of `epic-branch-protection.md`, "Pre-flight check": the ruleset is active, covers
`refs/heads/feature/epic/*`, has no bypass actor, and requires exactly the four checks, by the
names of the CI jobs. A missing or wrong ruleset stops the run with a report; the orchestrator
neither creates nor edits a ruleset and never goes on unprotected. A required check whose name
no job has blocks every PR into the epic branch for good, which is why the names are compared.

### Lifecycle

1. **Create** (orchestrator, after the checks of `running-an-epic.md`, step 1):
   `git fetch origin && git switch -c feature/epic/<slug> origin/main`, commit the plan's
   `Status` line as `running` (`chore(epic): start <slug>`), review it and run
   `scripts/pre-push-check.sh`, then push. That commit is the one pushed straight to the epic
   branch: the `pull_request` rule doesn't apply to creating the branch. Every later change
   arrives through a PR.
2. **Open the epic PR as a draft**, straight away:
   `gh pr create --draft --base main --head feature/epic/<slug>`, titled
   `feat(<scope>): <epic summary>`. The body contains the plan link, a status table (one
   row per subtask: branch, wave, state, PR #, who merged it; the table of
   `running-an-epic.md`) and the four `tm-pr-workflow` headings, filled in at the end. The
   orchestrator updates the status table as subtask PRs open and merge.
3. **Waves**: see "Waves" (`spawning-subtasks.md`) and the loop of `running-an-epic.md`, step 3.
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
