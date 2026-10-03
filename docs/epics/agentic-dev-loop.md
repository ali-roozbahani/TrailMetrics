# Epic: Agentic development loop

> **Amended 2026-10-03, approved by Ali Roozbahani.** S3 as built (workflow, check name,
> green for `APPROVE` and `ESCALATE_TO_HUMAN`); workflow files are pushed by the human; new
> Decision 8 (reading the CI verdict); Decisions 5 and 7 spell out the merge conditions and
> Decision 7 keeps "Allow auto-merge" off; S4 is split into S4a and S4b; S5 and S6 follow
> that. The text below is the plan as amended; the approval line keeps its original date.

- **Slug:** agentic-dev-loop
- **Integration branch:** none. A chain of plain PRs against `main`, each merged by the human.
- **Goal:** An agent can take the next task from `BOARD.md`, implement it, get an
  independent review, run the full local gate, open a PR, and, for tasks that touch no
  protected path and only after a trial period, merge it itself once CI and the reviewer
  agree. Protected paths and epics are always merged by the human.
- **Out of scope:** the test seam, UI test targets and the manual device checklist (they
  become their own epic with their own plan after S6); any app code; GitHub Apps; renaming
  the two existing required CI checks.
- **Approved by:** Ali Roozbahani on 2026-10-02

## Decisions

1. **Identities.** Agents work as a GitHub machine account (collaborator with write access,
   classic token with only the `repo` scope and no `workflow` scope, from its own clone).
   The GitHub Action reviewer uses the workflow's built-in token, and the human is the code
   owner. Because the machine token has no `workflow` scope, GitHub refuses its push of a
   change under `.github/workflows/`: any subtask that changes such a file is pushed by the
   human (the agent builds and verifies it locally, then hands over).
2. **Layers before a merge.** (a) A fresh-context reviewer subagent reviews locally before
   the push; (b) the full local gate runs the full test suite of every platform the diff
   touches; (c) push and PR; (d) CI re-runs the same tests on a clean machine and a GitHub
   Action review runs, both as required checks; (e) merge: the human during the trial,
   afterwards the agent for unprotected paths.
3. **Tests.** The local gate is the primary place where failures are found and fixed, before
   any push; CI runs the same tests on a clean environment as a second confirmation and, as
   a required check, blocks the merge when red. A red CI after a green local gate means the
   two disagree: find the root cause (and add a board record if it is real), do not just
   re-run.
4. **Protected paths.** The single source of truth is `.github/CODEOWNERS`, and
   `scripts/check-protected-paths.sh` classifies a diff from it. An agent never merges a PR
   that touches a protected path; the human does. What a path cannot express (deleted
   tests, `@Throws` declarations outside the shared module, anything else the reviewer
   judges critical) is enforced by the reviewer, which escalates it to the human.
5. **Epics.** Agents may merge subtask PRs into the epic branch with
   `gh pr merge --squash --match-head-commit <SHA>`, only when all of Decision 7's
   conditions hold except "touches no protected path": a subtask PR that touches a protected
   path may be merged into the epic branch only if the plan's `allowed_paths` for that
   subtask cover it. The epic merges into `main` only on the human's
   explicit command after the human's own testing, with
   `gh pr merge --match-head-commit <tested SHA>`; if the epic touches a protected path,
   the human also approves the PR on GitHub.
6. **After a merge.** The agent verifies the PR is `MERGED`, switches to `main`,
   fast-forwards it, deletes the local branch with `-D` (squash merges leave it unmerged by
   ancestry) and runs `git fetch --prune`. GitHub deletes the remote branch (repository
   setting "Automatically delete head branches").
7. **Auto-merge.** Enabled only after a trial of 5 consecutive PRs in which the reviewer's
   verdict and the human's decision agree (any disagreement restarts the count), and only
   for PRs that touch no protected path. The trial counts only PRs that touch no protected
   path: a protected PR always escalates and the human merges it, so agreement there proves
   nothing. After the trial the agent merges itself with
   `gh pr merge --squash --match-head-commit <SHA>`, and only when all of these hold: both
   required checks are green; the PR head is a branch of this repository; the author is the
   machine account; the CI annotation says `APPROVE` for that head SHA (Decision 8); the
   local reviewer's recorded verdict for that SHA is `APPROVE`; and the PR touches no
   protected path. GitHub's repository setting "Allow auto-merge" stays off permanently.
8. **Reading the CI verdict.** The `Review — pr-reviewer` check's conclusion cannot tell
   `APPROVE` from `ESCALATE_TO_HUMAN` (it is green for both), so an agent reads the verdict
   from the check run's annotation on the PR head SHA: level `notice` = `APPROVE`,
   `warning` = `ESCALATE_TO_HUMAN`, `failure` = `CHANGES`. This is to be proven on a real PR
   in S4b; if the verdict cannot be read that way, the plan is amended again.

## Subtasks

```yaml
- id: S1
  title: Commit the plan, define protected paths in CODEOWNERS, add the protected-path classifier
  branch: chore/agentic-loop-protected-paths
  skills: [tm-pr-workflow]
  depends_on: []
  allowed_paths:
    - docs/epics/agentic-dev-loop.md
    - .github/CODEOWNERS
    - scripts/check-protected-paths.sh
    - scripts/check-protected-paths.py
    - .claude/skills/tm-pr-workflow/SKILL.md   # Boundaries section only
    - BOARD.md                                 # the agentic-dev-loop record only
  acceptance:
    - .github/CODEOWNERS lists every protected path, all owned by @ali-roozbahani.
    - scripts/check-protected-paths.sh prints `protected` or `unprotected` and the matching
      files for a diff or a file list, validates CODEOWNERS, and has a passing --self-test
      that was shown failing against a deliberately broken matcher.
    - tm-pr-workflow's Boundaries point to CODEOWNERS and the script instead of a hand-written list.
  tier2: none

- id: S2
  title: Add the local reviewer subagent and its review checklist
  branch: chore/agentic-loop-local-reviewer
  skills: [tm-pr-workflow]
  depends_on: [S1]
  allowed_paths:
    - .claude/agents/**
    - .claude/skills/<review-checklist-skill>/**
    - scripts/pre-push-check.sh   # the soft verdict step only
  acceptance:
    - A reviewer subagent definition under .claude/agents/ runs with a fresh context and
      read-only tools.
    - A review checklist skill covers the task's Done when, the repo skills, protected
      paths, a red test for bugfixes, deleted tests, @Throws and the SKIE boundary, new
      dependencies, board bookkeeping and no line numbers.
    - The verdict is APPROVE, CHANGES or ESCALATE_TO_HUMAN and is recorded for the
      reviewed HEAD SHA.
    - A soft gate step reports whether a verdict exists for HEAD.
  tier2: none

- id: S3
  title: Add the GitHub Action reviewer
  branch: chore/agentic-loop-action-reviewer
  skills: [tm-pr-workflow]
  depends_on: [S2]
  allowed_paths:
    - .github/workflows/pr-review.yml
  acceptance:
    - The workflow reviews PRs from branches of this repository with the S2 checklist,
      read-only, treating PR content as untrusted data.
    - It reports its result as the check `Review — pr-reviewer`, which is green for both
      `APPROVE` and `ESCALATE_TO_HUMAN` (the verdict itself is in the annotation, Decision 8),
      and cannot approve or merge.
    - The human sets the API key secret and a spending limit. The check is not required
      until S5.
    - Pushed by the human (Decision 1, no `workflow` scope).
  tier2: none

- id: S4a
  title: Wire the classifier into the gate and CI, deny credential reads, amend the plan
  branch: chore/agentic-loop-gate-wiring
  skills: [tm-pr-workflow, tm-pr-review]
  depends_on: [S3]
  allowed_paths:
    - scripts/pre-push-check.sh
    - .github/workflows/ci.yml                 # one step in the android job
    - .claude/settings.json
    - .claude/skills/tm-pr-review/SKILL.md     # the review input directory command only
    - .claude/skills/tm-pr-workflow/SKILL.md   # Tier 1 section only
    - docs/epics/agentic-dev-loop.md
    - BOARD.md                                 # agentic-dev-loop and drift-tier1-gate-steps-omit-review-verdict only
  acceptance:
    - check-protected-paths.sh --validate and --self-test run, blocking, in the gate and in
      CI's android job; the gate also prints the diff's classification, report only.
    - Deny rules stop the agent from reading other credentials.
    - tm-pr-review fills its input directory without deleting through an unchecked variable.
    - tm-pr-workflow's Tier 1 lists the protected-paths and review verdict steps.
    - This plan carries the 2026-10-03 amendments.
    - Pushed by the human (Decision 1, no `workflow` scope).
  tier2: the new CI step is green on the PR and the two required check names are unchanged

- id: S4b
  title: Add the loop skill and align the skills with the Decisions
  branch: chore/agentic-loop-skill
  skills: [tm-pr-workflow, epic-orchestration]
  depends_on: [S4a]
  allowed_paths:
    - .claude/skills/<loop-skill>/**
    - .claude/skills/epic-orchestration/SKILL.md
    - .claude/skills/tm-pr-workflow/SKILL.md
    - CLAUDE.md                                # the skill list only
    - BOARD.md                                 # narrow auto-merge-requires-approve-verdict only
  acceptance:
    - The loop skill covers picking the task with `scripts/check-board.sh --next` (aware of
      `scripts/check-protected-paths.sh`), implement, local review, fix, gate, push, PR, the
      retry budget and escalation to the human, reading the CI annotation (Decision 8),
      after-merge cleanup (Decision 6) and the merge conditions of Decisions 5 and 7.
    - epic-orchestration and tm-pr-workflow match the Decisions above, including their old
      lines that say no agent merges any PR.
    - CLAUDE.md's skill list names the loop skill.
    - Proof on a real PR that the verdict can be read from the check run's annotation for
      the head SHA (Decision 8); otherwise the plan is amended again.
  tier2: none

- id: S5
  title: Turn on code owner review and the review check in main's branch protection (human, no PR)
  branch: none
  skills: []
  depends_on: [S4b]
  allowed_paths: []
  acceptance:
    - "Require review from Code Owners" and the review check are required on main.
    - A throwaway PR shows a protected-path change is blocked for the agent account, and
      the two existing required checks are unchanged.
    - Open question, verified here: whether the code owner requirement applies when the
      required approval count is 0. Fallback: 1 required approval.
  tier2: the throwaway PR above

- id: S6
  title: Run the trial, then document auto-merge for unprotected paths
  branch: chore/agentic-loop-auto-merge
  skills: [tm-pr-workflow]
  depends_on: [S5]
  allowed_paths:
    - .claude/skills/**
  acceptance:
    - 5 consecutive board tasks that touch no protected path are done by the loop with the
      human merging, and the reviewer's verdict agreed with the human's decision on each
      (Decision 7; PRs that touch a protected path do not count).
    - Afterwards one small PR documents auto-merge for unprotected paths under the
      conditions of Decision 7. The repository setting "Allow auto-merge" stays off.
  tier2: none
```

## Waves

- S1, S2, S3, S4a, S4b, S5, S6, strictly one after another (each builds on the previous
  one, and S2 to S4b all edit the same skills and gate).

## Epic-level Tier 2

- The human watches one full loop end to end: next task, reviewer verdict, gate, PR, both
  checks, merge, cleanup.
- The human confirms a protected-path PR is blocked for the agent account.
