---
name: epic-orchestration
description: Use when a TrailMetrics change is big enough to split across layers or platforms (e.g. a shared-layer change plus separate Android and iOS UI work) and should run as a multi-agent epic, or an approved epic the owner starts with "run the epic <slug>". Covers deciding epic vs. single task, writing the human-reviewed plan (subtasks, depends_on, allowed_paths, acceptance criteria), allowed_paths conventions for this repo's modules, integration branch naming, lifecycle and protection, spawning and scoping parallel subtask agents, integrating each subtask locally into the integration branch, the conditions for merging the epic PR into main, and the whole run of an approved epic from one command (running-an-epic.md). Not for per-PR mechanics (see tm-pr-workflow) or how to write the code (see tm-kmp-shared, tm-android, tm-ios, tm-testing).
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
| `running-an-epic.md` ("The command", the steps 1 to 5, "Evidence", "The queue and the epic", "What the owner does") | the owner says "run the epic `<slug>`", or a run of an epic resumes: the whole procedure from the checks to the epic PR that is open and green |
| `spawning-subtasks.md` ("Spawning subtask agents", "Waves", "Workers", "Isolation", "What a subtask worker is told") | the first wave is about to start: which subtasks are ready, disjointness, the worktrees, the task file |
| `subtask-merge.md` ("Integrating a subtask") | a worker has finished and its subtask is reviewed, gated and merged into the integration branch |
| `merging-the-epic.md` ("Merging the epic into main") | every subtask is merged into the integration branch and the epic PR into `main` is prepared |


## The command

The owner starts an approved epic with one sentence: "run the epic `<slug>`". The orchestrator then runs the whole epic
by `running-an-epic.md` and asks for nothing else: it checks what has to be checked, creates the integration branch, runs the
waves in the order the plan's `depends_on` gives, merges each subtask locally into the integration branch after its own local
review and gate, pushes the branch once and opens the one epic PR, watches its CI, fixes what CI finds, and ends with the epic PR
open, green and waiting for the owner, and a report. The same sentence resumes a run that stopped, and carries the owner's decision when the run stopped for one ("run the epic `<slug>`, S4: accept the escalation"): `running-an-epic.md`, "The owner's decisions at a stop". Without that command, an
epic whose plan is approved stays as it is (`tm-agent-loop`, section 1).

**The owner's decision of 2026-11-19, and a hypothesis:** a subtask is **not** a PR. There is no per-subtask PR and no per-subtask CI.
The local merge and the local gate are much faster than GitHub's CI, so a CI run per subtask mostly buys waiting; one CI run on the final PR is
enough and necessary; and the owner is asked to review and merge one PR, not several. The first run has to test this, not assume it:
`running-an-epic.md`, "Evidence", says what it records, and the owner changes the decision if the evidence says he was wrong.

## Roles

- **Human**: approves the plan (by merging the PR that adds it to `main`) and every change to it, deletes the ruleset for `feature/epic/*`
  if there is one, says "run the epic `<slug>`", does the human part of Tier 2 (the epic's final smoke check and any human check the epic PR
  lists with its reason, `tm-pr-workflow`, "Tier 2: what automated tests cannot show"), reviews the epic PR and merges it into `main` (only the
  human).
- **Orchestrator**: the Claude Code session the human is talking to. It drafts the plan, and on the command "run the epic `<slug>`" it creates the
  integration branch, starts a worker for each subtask wave by wave, integrates every worker's commits (the local review, the gate, the local merge),
  checks that each subtask stayed inside its `allowed_paths`, keeps the run record, and at the end pushes the branch once, opens the epic PR and
  watches its CI. It writes no feature code itself.
- **Subtask worker**: one `implementer` per subtask (`tm-agent-loop`, "Subagents"), in its own worktree made by `scripts/subagent/worktree.sh`, with the
  subtask's `allowed_paths` as its allowed paths. It writes code and commits to the worktree's branch, and nothing else: it opens no PR, runs no gate and
  starts no subagent. The orchestrator integrates it, because the local review needs a subagent (the reviewer) and nothing below the orchestrator spawns
  (`tm-agent-loop`, "Subagents", "Nesting"), and `tm-agent-loop`, "Never", forbids a subagent to push or open a PR.

The epic PR into `main` is the human's only, on the human's explicit command (`docs/epics/agentic-dev-loop.md`, Decision 5). The subtasks are not PRs, so
no agent merges anything on GitHub in an epic: the orchestrator merges the subtask branches locally, and the human merges the one PR.

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
  the plan's approval; the integration branch is created after it. See "The plan" and Lifecycle step 1.
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

An epic's plan is a committed file, `docs/epics/<epic-slug>.md`. It is on `main` before the integration
branch exists (the PR that adds it is the human's to merge; its merge, with the "Approved by" line
filled, is the approval). The plan is also the record in history of how the epic was split. (Whether
`docs/epics/` is protected is decided by `.github/CODEOWNERS`; check with
`scripts/check-protected-paths.sh --files`.) The file records **decisions**. The live state of a run is
the integration branch and the run record (`running-an-epic.md`), so that nothing edits the plan file
during a run except the orchestrator's board commit at the end, which sets its `Status` to `done`.

### Workflow

1. The orchestrator drafts the plan in chat or a scratch file and shows it to the human.
   It doesn't create a branch or spawn anything yet.
2. The human reviews and approves it (or edits it). **No subtask starts before this.**
3. The plan is merged into `main` by the human. On the command "run the epic `<slug>`" the
   orchestrator creates the integration branch (see Lifecycle).
4. Any later change to `depends_on`, `allowed_paths` or acceptance criteria needs the
   human to approve it again, and gets its own `chore(epic)` commit to the plan file on
   the integration branch, which travels in the epic PR.

### Format

The plan file's format, and a worked example (personal records on History), are in
`plan-format.md`.

## Integration branch

### Naming

**`feature/epic/<epic-slug>`**. Each part of the name is there for a reason:

- **`feature/` prefix, so CI runs.** `ci.yml` triggers `push` for `main` and `feature/epic/**`, and `pull_request`
  for base branches matching `main` or `feature/**`. The epic PR is against `main`, and a push of the
  integration branch also starts CI: it is pushed once, when the epic PR is opened, and never as a backup.
- **`epic/` segment, so a rule or a CI trigger can target integration branches without catching
  subtask branches.** The pattern `feature/epic/*` matches the integration branch. It doesn't match
  subtask branches named `<type>/<epic-slug>-<subtask>`.
- Subtask branches can't live *under* the epic branch (`feature/epic/<slug>/s1`), because
  git can't have a ref and a directory with the same name. So they're siblings:
  `<feature|bugfix|chore>/<epic-slug>-<subtask-slug>`. They are local and are never pushed.
- No ref named exactly `feature/epic` may ever exist, or the prefix becomes unusable.

### Protection

There is **no ruleset and no branch protection for epic branches** (the owner's decision of 2026-11-19). The integration branch is local until the
epic PR is opened, and `main`'s own protection (PR required, the four required checks, strict, `enforce_admins`) guards the epic PR. A ruleset on
`feature/epic/*` that requires a pull request and passing checks would refuse a fix pushed to the open epic PR after a red CI, so none may be active
while an epic runs. The owner deletes it himself; the orchestrator never creates, edits or deletes a ruleset.

**Pre-flight check for the orchestrator:** before it creates the integration branch it checks that no active ruleset applies to `feature/epic/<slug>` and
requires a pull request or status checks (`epic-branch-protection.md`, "Pre-flight check"). One that does stops the run with a report that tells the owner to delete it.

### Lifecycle

1. **Create** (orchestrator, after the checks of `running-an-epic.md`, step 1):
   `git fetch origin && git switch -c feature/epic/<slug> origin/main`. The branch is local and has no commit of its own yet; nothing is pushed.
2. **Waves**: see "Waves" (`spawning-subtasks.md`) and the loop of `running-an-epic.md`, step 3. Each subtask is merged locally into the
   branch (`subtask-merge.md`).
3. **Keeping up with `main`**: if `main` moved while the run goes, the branch takes `main` once, at the end, before the final review (`git merge origin/main`,
   its own tool call; no rebase, which would rewrite the commits that subtask branches are based on). Conflicts are resolved there, within the scope that the
   conflicting files' owners had.
4. **Finish**: the board commit, the final local review and gate of the whole branch, one push, the one epic PR (`merging-the-epic.md`).
5. **After merge**: GitHub deletes the remote epic branch on merge ("Automatically delete head branches" is on). The local branch and the run record are the
   agent's cleanup at the start of the next run (`tm-pr-workflow`, "Before starting").

**Abandoning an epic**: the human closes the epic PR if one is open, and the local branch is deleted. Nothing reached `main`, which is the point of having an
integration branch.

## Where this skill made calls the retired workflow doc didn't

Recorded so the first real epic can confirm or correct them: `decisions-history.md`.
