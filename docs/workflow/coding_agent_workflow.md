# Coding agent workflow

This document defines the standard process for delegating a feature, bug
fix, or chore to a coding agent (Claude Code or any equivalent tool) on
this project. It exists so every task starts from the same context and
follows the same standing rules — regardless of which tool, which day, or
who wrote the task prompt. The task prompt itself only needs to state
*what* to do; *how* to do it (branching, testing, commit/push/PR
boundaries) lives here, once.

## Before assigning any task

`CLAUDE.md` at the repo root is loaded automatically and points to the
relevant Skill(s) under `.claude/skills/` for the module(s) being touched
(`tm-kmp-shared`, `tm-android`, `tm-testing`). The agent is expected to
follow those Skills plus this document without needing them repeated in
the task prompt. Also read:
- `docs/architecture/OVERVIEW.md` — module graph and platform strategy.
- The relevant platform guide under `docs/coding-standards/`.
- The `README.md` of every module the task touches.
- `LEARNINGS.md`, for known gotchas relevant to KMP/Xcode/Gradle
  integration.

## Standing rules

These apply to every task automatically. The task prompt does not need to
restate them.

### Branching

- Always create and check out a new branch before making any changes.
  Never leave prepared changes sitting on the branch you started from.
- Branch name = `<type>/<slug>`:
  - `feature/<slug>` — new functionality
  - `bugfix/<slug>` — fixing a defect
  - `chore/<slug>` — tooling, docs, config, dependency bumps, refactors
    with no behavior change
- Branch from `main`, unless the task explicitly names a different base
  (e.g. an epic's integration branch — see "Multi-agent epics" below).

### Verification (Tier 1 vs. Tier 2)

- **Tier 1 — the agent's responsibility.** Before pushing, the agent runs
  `scripts/pre-push-check.sh` and only pushes once it exits 0. That script
  runs `detekt`, Android `lint`, `test`, `assembleDebug` always, plus
  SwiftLint and an iOS build when the diff touches `iosApp/` or a shared
  module (`domain/`, `data/`, `core/`, `shared/`). A `PreToolUse` hook
  (`.claude/settings.json` → `scripts/claude-hooks/block-git-push.sh`)
  enforces this mechanically: `git push` is blocked unless the gate script
  has passed since the last commit. A task is not "done" until Tier 1 has
  been run and reported, even if the task prompt didn't spell it out.
- **Retry budget:** if `scripts/pre-push-check.sh` still fails after **2**
  fix attempts, the agent stops, reports what's failing and what it tried,
  and waits — it does not keep looping indefinitely against local checks
  or push anyway.
- **Tier 2 — the human's responsibility.** Manual verification on a
  simulator/emulator/device — actually running the feature, checking it
  looks and behaves right. This is never delegated to the agent, and it
  happens before merge to `main` (see below).

### Commit, push & PR

- The agent commits and pushes to the branch it created, and opens a PR
  once Tier 1 passes. It does this on its own initiative — the task
  prompt does not need to ask for it separately.
- The agent **never** pushes directly to `main` and never merges a PR
  into `main`, under any circumstances. `main` is branch-protected
  (required status checks + review) so this is also enforced mechanically,
  not just by convention.
- Merging to `main` happens only after both Tier 1 (CI green, mirroring
  the already-passed local gate) and Tier 2 (human manual verification)
  pass. The human merges.
- PR description states: what changed, which Skills/docs were followed,
  Tier 1 results, and anything Tier 2 should specifically check.
- Commit messages: `type(scope): summary` — see recent git history for
  the established `type` vocabulary (`feat`, `fix`, `refactor`, `build`,
  `docs`, `test`).

### Multi-agent epics

For a task large enough to be split across platforms or layers (e.g. a
shared-layer change plus independent Android and iOS UI work), an epic is
planned before any implementation agent runs:
1. A plan (subtasks, `depends_on` ordering, `allowed_paths` per subtask,
   acceptance criteria) is written and reviewed by the human before any
   subtask starts.
2. Subtasks with no shared `allowed_paths` and no unmet `depends_on` may
   run in parallel, each in its own branch/worktree, each opening its own
   PR against the epic's integration branch (not `main`).
3. All the standing rules above (branching prefix, Tier 1 gate, no direct
   `main` push) apply per subtask.
4. Once every subtask is merged into the epic branch and Tier 2 passes on
   the integrated result, the human merges the epic branch into `main`.

### Boundaries

- Never change `docs/architecture/*`, `shared_conventions.md`, this file,
  CI config, or lint config as a side effect of an unrelated task — those
  changes go through their own explicit task and review.
- Never introduce a new third-party dependency unless it's called out
  explicitly in the task's scope.
- Never cross a module boundary flagged in `shared_conventions.md` or in
  the `tm-kmp-shared` Skill — if a task seems to require it, say so and
  stop rather than work around it.
- If something in the existing docs/conventions is ambiguous or missing
  for the task at hand, state the assumption made rather than silently
  picking one.
- Follow the existing module's structure and naming exactly, matching
  whatever reference pattern the task's Context section points to —
  unless that reference itself is flagged as not yet migrated to a
  current target pattern (e.g. pre-MVI ViewModels; see `tm-android`).

## Standard task prompt template

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

## After the agent produces changes

1. CI runs on the PR (mirrors `scripts/pre-push-check.sh`, so it should
   already be green).
2. The human performs Tier 2 verification: runs the app on a
   simulator/emulator/device and checks the feature actually works.
3. The human does a structural review of the diff — does it match the
   established pattern, does it respect module boundaries, is anything
   duplicated that should be shared.
4. Only after both Tier 2 and structural review pass does the human merge
   the PR into `main`.
