# Coding agent workflow

This document defines the standard process for delegating a feature, bug
fix, or chore to a coding agent (Claude Code or any equivalent tool) on
this project. It exists so every task starts from the same context and
follows the same standing rules — regardless of which tool, which day, or
who wrote the task prompt. The task prompt itself only needs to state
*what* to do; *how* to do it (branching, testing, commit/merge boundaries)
lives here, once.

## Before assigning any task

The agent must read, in this order:
1. `docs/architecture/OVERVIEW.md` — module graph and platform strategy.
2. The relevant platform guide: `docs/coding-standards/android_developer_guide.md`
   or `ios_developer_guide.md`.
3. `docs/coding-standards/shared_conventions.md`.
4. **This document** (`docs/workflow/coding_agent_workflow.md`) — the
   standing rules below apply to every task, whether or not the task
   prompt repeats them.
5. The `README.md` of every module the task touches.
6. `LEARNINGS.md`, for known gotchas relevant to KMP/Xcode/Gradle
   integration.

## Standing rules

These apply to every task automatically. The task prompt does not need to
restate them — the agent is expected to have read this document and
follow them regardless.

### Branching

- Always create and check out a new branch before making any changes.
  Never leave prepared changes sitting on the branch you started from.
- Branch name = `<type>/<slug>`, using whichever prefix fits the task:
  - `feature/<slug>` — new functionality
  - `bugfix/<slug>` — fixing a defect
  - `chore/<slug>` — tooling, docs, config, dependency bumps, refactors
    with no behavior change
  - For KMP migration phase work specifically, use the more specific
    `feature/kmp-phase-<letter>-<slug>` form (a subtype of `feature/`).
- Branch from the current branch (usually `feature/kmp-migration-main`
  during the migration, `main` once it's complete) unless the task says
  otherwise.

### Verification (Tier 1 vs. Tier 2)

- **Tier 1 — the agent's responsibility.** Before handing work back, the
  agent implements and runs the relevant linters and automated tests
  (`./gradlew detekt`, `./gradlew test`, `swiftlint lint --strict`, and
  any unit/integration tests the change should reasonably include or
  update) and reports the results. A task is not "done" if Tier 1 hasn't
  been run and reported, even if it wasn't spelled out in that task's
  prompt.
- **Tier 2 — the human's responsibility.** Manual verification on a
  simulator/emulator/device — actually running the feature, checking it
  looks and behaves right. This is never delegated to the agent.

### Commit & merge

- The agent never commits, pushes, or merges, under any circumstances,
  even if the task prompt forgets to say so. It prepares the changes on
  the branch it created and stops.
- Only after Tier 1 (agent-run) and Tier 2 (human-run) both pass does the
  human commit and merge, following the conventions in
  `shared_conventions.md`.

### Boundaries

- Never change `docs/architecture/*`, `shared_conventions.md`, this file,
  or CI/lint config files as a side effect of an unrelated task — those
  changes go through their own explicit task and review.
- Never introduce a new third-party dependency unless it's called out
  explicitly in the task's scope.
- Never cross a module boundary flagged in `shared_conventions.md` — if a
  task seems to require it, say so and stop rather than work around it.
- If something in the existing docs/conventions is ambiguous or missing
  for the task at hand, state the assumption made rather than silently
  picking one.
- Follow the existing module's structure and naming exactly, matching
  whatever reference pattern the task's Context section points to.

## Standard task prompt template

Since the standing rules above already govern every task, the prompt
itself only needs to specify what's actually task-specific:

```
Task: <one-line description of the feature, fix, or chore>

Context:
- Read `docs/workflow/coding_agent_workflow.md` in full before doing
  anything else — it lists the required reading order (architecture,
  platform guide, shared conventions) and the standing rules (branching,
  verification tiers, commit/merge boundaries) that govern this task.
- Reference implementation (if porting a feature): <path to the Android or
  iOS equivalent, e.g. androidApp/feature-history/>
- Module(s) this task touches: <list>
- Anything else specific to this task the agent wouldn't otherwise know
  (e.g. "assume X was already added in a prior task — if missing, stop
  and flag it")

Scope:
<what should change, and explicitly what should NOT change>

Branch: <type>/<slug>
```

## After the agent produces changes

1. The human pastes the diff, plus the agent's Tier 1 report (lint/test
   results), into the review conversation (with Claude, or whichever
   assistant is doing architectural review) for a structural check — does
   it match the established pattern, does it respect module boundaries,
   is anything duplicated that should be shared.
2. The human performs Tier 2 verification: runs the app on a
   simulator/emulator/device and checks the feature actually works.
3. Only after both the structural review and Tier 2 pass does the human
   commit and merge.
