# Coding agent workflow

This document defines the standard process for delegating a feature or bug
fix to a coding agent (Claude Code or any equivalent tool) on this project.
It exists so every task starts from the same context and produces
consistent, reviewable output — regardless of which tool or which day.

## Before assigning any task

The agent must read, in this order:
1. `docs/architecture/OVERVIEW.md` — module graph and platform strategy.
2. The relevant platform guide: `docs/coding-standards/android_developer_guide.md`
   or `ios_developer_guide.md`.
3. `docs/coding-standards/shared_conventions.md`.
4. The `README.md` of every module the task touches.
5. `LEARNINGS.md`, for known gotchas relevant to KMP/Xcode/Gradle
   integration.

If a prompt template (below) is used, step 1–3 are referenced explicitly so
the agent doesn't have to be told this separately every time.

## Standard task prompt template

```
Task: <one-line description of the feature or fix>

Context:
- Read docs/architecture/OVERVIEW.md, docs/coding-standards/<platform>_developer_guide.md,
  and docs/coding-standards/shared_conventions.md before writing any code.
- Reference implementation (if porting a feature): <path to the Android or
  iOS equivalent, e.g. androidApp/feature-history/>
- Module(s) this task touches: <list>

Scope:
<what should change, and explicitly what should NOT change>

Branch: <branch name, following the feature/kmp-phase-<letter>-<slug> convention>

Rules:
- Do not commit. Do not merge. Prepare the changes and stop.
- Follow the existing module's structure and naming exactly (see
  <specific file to mirror> as the pattern to follow).
- If something in the existing docs/conventions is ambiguous or missing
  for this task, state the assumption made rather than silently picking one.
```

## After the agent produces changes

1. The human pastes the diff into the review conversation (with Claude, or
   whichever assistant is doing architectural review) for a structural
   check — does it match the established pattern, does it respect module
   boundaries, is anything duplicated that should be shared.
2. The human runs the relevant lint/build/test commands locally
   (`./gradlew detekt`, `./gradlew test`, `swiftlint lint --strict`, a
   Simulator/emulator run) — CI is a backstop, not the first line of
   defense.
3. Only after both the structural review and a working local test pass
   does the human commit and merge, following the branch/commit
   conventions in `shared_conventions.md`.

## What the agent must never do unprompted

- Commit or push.
- Merge a branch.
- Change `docs/architecture/*`, `shared_conventions.md`, or CI/lint config
  files as a side effect of an unrelated feature task — those changes go
  through their own explicit task and review.
- Introduce a new third-party dependency without it being called out
  explicitly in the task scope.
- Cross a module boundary flagged in `shared_conventions.md` — if the task
  seems to require it, the agent should say so and stop rather than work
  around it.
