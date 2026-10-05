# Epic: Protected paths review

- **Slug:** protected-paths-review
- **Integration branch:** none. A chain of plain PRs against `main`, each merged by the human
  (every PR in this epic touches a protected path, so none counts toward the S6 trial).
- **Goal:** Narrow the protected set so that PRs which only update reference documentation
  or raise a coverage floor no longer escalate to the human, without opening a way for an
  agent to weaken the rules it is judged by. The guardrails (gate, workflows, reviewer,
  process skills, agent settings, dependency catalog) stay protected.
- **Out of scope:** module `build.gradle.kts` files other than the coverage floor (they hold
  executable Gradle code and dependency changes), `gradle/`, `shared/`, the persistence
  paths, `docs/architecture/` and `docs/epics/` (all stay protected), the test seam and UI
  tests (their own tasks on the board), any app code, GitHub repository settings, and
  `LEARNINGS.md` (it is not protected today and stays unprotected).
- **Approved by:** Ali Roozbahani on 2026-10-06

## Why

Today `/.claude/` (every skill, the agent definition and settings) and every
`build.gradle.kts` are protected. Two kinds of change fall under that for no safety reason:
(a) a factual line in a reference skill that a code change made wrong (board rule 2 forces
this when a record that a skill names is deleted), and (b) raising a Kover floor. Such PRs
escalate to the human, do not count toward the S6 trial and cannot be merged by an agent
after it. At the same time the skills are the agent's persistent instructions, so an
unreviewed edit that weakens a rule is a real risk: the CI reviewer reads rules from the
base branch, so a PR cannot change the rules it is judged by, but it can weaken a rule in
one PR and be judged by the weakened rule in the next. This plan opens the first two and
closes that gap mechanically.

## Decisions

1. **Stays protected (guardrails).** `.github/`; `CLAUDE.md`; everything under `.claude/`
   except the reference skills in Decision 2 (so `.claude/agents/`, settings, hooks, commands
   and any new path under `.claude/` stay protected by default); the process skills
   `tm-agent-loop`, `tm-pr-review`, `tm-pr-workflow` and `epic-orchestration`; the gate and
   its tooling under `scripts/`; `gradle/` (the version catalog is where a new dependency
   must enter); `settings.gradle.kts`, `Package.swift`, `Package.resolved`; module
   `build.gradle.kts` files; `shared/`; the persistence paths; `docs/architecture/`;
   `docs/epics/`; `config/detekt/`; `iosApp/.swiftlint.yml`; the Xcode project.
2. **Becomes unprotected (reference skills).** `.claude/skills/tm-ios/`,
   `.claude/skills/tm-android/`, `.claude/skills/tm-kmp-shared/`,
   `.claude/skills/tm-testing/`. They describe how the code is written; the process rules
   live in the skills of Decision 1. An edit to them is judged by the reviewer like any other
   file in the diff, with the extra rule of Decision 3.
3. **Rule-weakening signal.** A new script `scripts/check-skill-rule-changes.sh` (with a
   `--self-test` and fixtures) reads a diff and lists every removed or rewritten line, in any
   file under `.claude/skills/` or in `CLAUDE.md`, that contains a rule word (`must`, `never`,
   `always`, `do not`, `don't`, `required`, `forbidden`, `only`, `at most`, `at least`) or a
   number inside such a line. Removed lines whose text reappears unchanged elsewhere in the
   same file are ignored (moved lines). The reviewer receives the list as a deterministic
   input, taken from the base branch like the classifier. A non-empty list is
   `ESCALATE_TO_HUMAN` with a finding named `rule-weakened`, unless the task text names
   that exact change. Additions and purely factual edits pass. The signal runs from the base
   branch, so a PR cannot edit it to pass.
4. **Coverage floors become a ratchet.** The five Kover floors (`domain`, `data`,
   `feature-route`, `feature-tracking`, `feature-history`) move out of the module
   `build.gradle.kts` files into one file `config/kover-floors.properties`, read by the build.
   The file is unprotected. A new script `scripts/check-kover-floors.sh` (with `--self-test`
   and fixtures) compares it with the base branch and fails when any floor is lower than on
   the base, when a module with a Kover rule has no entry, or when an entry has no module.
   It runs in the gate and in CI. Lowering a floor is not supported by the mechanism: it
   needs a human PR that changes the script (protected). The human raises or sets the
   initial values from the measured coverage; the S1 PR keeps every current value.
5. **CODEOWNERS.** `/.claude/` stays as the default, and the four reference skills are listed
   after it as paths with no owner, which GitHub treats as not owned. `scripts/check-protected-paths.sh`
   learns that syntax (the later, more specific line wins, as GitHub does) with self-test
   cases, and `--validate` rejects an ownerless line outside `.claude/skills/tm-*/`. Every
   new script of this epic gets its own owned entry.
6. **Visibility after the fact.** A script `scripts/skill-changes-digest.sh [--since DATE]`
   prints, for `.claude/skills/` and `CLAUDE.md`, the commits since a date with their PR
   titles and the changed lines. The human runs it when he wants (suggested weekly) and can
   revert anything. It is not a workflow and does not change merge rules.
7. **Interaction with the trial and board rules.** PRs of this epic are protected and do not
   count. After S3, a PR that edits only reference skills and passes the reviewer with
   `APPROVE` is unprotected and counts toward the trial like any other. Board rule 2 stays
   as written; it now produces a protected PR only when the skill named is a process skill.
8. **Changes to `.github/workflows/`** are pushed by the human (Decision 1 of
   `docs/epics/agentic-dev-loop.md`): the agent builds and verifies locally, stops before
   the push, and the human pushes the branch and tells the agent.
9. **Amendment of the earlier plan.** `docs/epics/agentic-dev-loop.md` Decision 4 gets one
   sentence pointing here: the protected set is defined by `.github/CODEOWNERS` and was
   narrowed by this epic; nothing else in that plan changes.

## Subtasks

```yaml
- id: S1
  title: Plan, board record, and the earlier plan's pointer
  branch: chore/protected-paths-review-plan
  skills: [tm-pr-workflow, epic-orchestration]
  depends_on: []
  allowed_paths:
    - docs/epics/protected-paths-review.md
    - docs/epics/agentic-dev-loop.md   # Decision 4: one sentence
    - BOARD.md
  acceptance:
    - This plan is committed verbatim as the human saved it, including its "Approved by" line.
    - BOARD.md has an epic record with this slug at an unused Order between 40 and 45.
    - check-board.sh passes.
  tier2: none

- id: S2
  title: Coverage floors in one file, with a ratchet check
  branch: chore/kover-floors-ratchet
  skills: [tm-pr-workflow, tm-testing]
  depends_on: [S1]
  allowed_paths:
    - config/kover-floors.properties
    - androidApp/feature-route/build.gradle.kts
    - androidApp/feature-tracking/build.gradle.kts
    - androidApp/feature-history/build.gradle.kts
    - data/build.gradle.kts
    - domain/build.gradle.kts
    - scripts/check-kover-floors.sh
    - scripts/check-kover-floors-fixtures/
    - scripts/pre-push-check.sh
    - .github/workflows/ci.yml
    - .github/CODEOWNERS
    - .claude/skills/tm-pr-workflow/SKILL.md
    - .claude/skills/tm-testing/SKILL.md
    - BOARD.md
  acceptance:
    - Every module reads its floor from config/kover-floors.properties and `koverVerify` still passes with the same values.
    - check-kover-floors.sh fails (shown) on a lowered floor, a missing entry and an extra entry, and passes on equal or raised floors; its self-test was shown failing against a deliberately broken comparison.
    - The gate and the CI Android job run it; the base for the comparison is the PR's merge base.
    - Phase split: the agent stops before the push (ci.yml); the human pushes.
  tier2: none

- id: S3
  title: Rule-weakening signal for the reviewer
  branch: chore/skill-rule-change-signal
  skills: [tm-pr-workflow, tm-pr-review]
  depends_on: [S1]
  allowed_paths:
    - scripts/check-skill-rule-changes.sh
    - scripts/check-skill-rule-changes-fixtures/
    - scripts/pre-push-check.sh
    - .github/workflows/pr-review.yml
    - .github/CODEOWNERS
    - .claude/agents/pr-reviewer.md
    - .claude/skills/tm-pr-review/SKILL.md
    - .claude/skills/tm-pr-workflow/SKILL.md
    - scripts/check-pr-review-workflow.py
    - scripts/check-pr-review-workflow-fixtures/
    - BOARD.md
  acceptance:
    - The script lists removed or rewritten rule lines for skills and CLAUDE.md, ignores additions and moved lines, and its self-test was shown failing against a deliberately broken matcher.
    - The CI reviewer and the local reviewer both receive its output, computed from the base branch's copy of the script.
    - tm-pr-review makes a non-empty list `ESCALATE_TO_HUMAN` with the finding `rule-weakened`.
    - Phase split: the agent stops before the push (pr-review.yml); the human pushes.
  tier2: none

- id: S4
  title: Open the reference skills, add the digest
  branch: chore/open-reference-skills
  skills: [tm-pr-workflow, tm-pr-review]
  depends_on: [S2, S3]
  allowed_paths:
    - .github/CODEOWNERS
    - scripts/check-protected-paths.sh
    - scripts/check-protected-paths.py
    - scripts/skill-changes-digest.sh
    - scripts/check-protected-paths-fixtures/
    - .claude/skills/tm-pr-workflow/SKILL.md   # Boundaries
    - .claude/skills/tm-agent-loop/SKILL.md    # where it says skills are protected
    - .claude/skills/tm-pr-review/SKILL.md     # item 3
    - BOARD.md
  acceptance:
    - A diff that touches only a reference skill classifies `unprotected`; a diff that touches any other file under `.claude/` classifies `protected`; both shown with real `check-protected-paths.sh --files` runs and in the self-test.
    - `--validate` rejects an ownerless line outside the four reference skill paths (shown).
    - A throwaway local diff that deletes a `must` line from a reference skill produces a non-empty `check-skill-rule-changes.sh` list (shown), so it would escalate.
    - skill-changes-digest.sh prints the commits and changed lines for a date range (shown on this repository's history).
    - The skills' text about what is protected matches CODEOWNERS.
  tier2: none
```

## Waves

S1, then S2 and S3 in either order (they share only `scripts/pre-push-check.sh` and
`.github/CODEOWNERS`, so one at a time), then S4. One PR at a time.

## Epic-level Tier 2

None: no app behavior changes. The human checks, after S4, that a throwaway PR editing one
reference skill is classified `unprotected` and one editing `tm-pr-review` is `protected`
(the commands are in S4's proof), and runs `scripts/skill-changes-digest.sh` once.
