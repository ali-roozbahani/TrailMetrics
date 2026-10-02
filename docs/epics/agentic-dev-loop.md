# Epic: Agentic development loop

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
   owner.
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
5. **Epics.** Agents may merge subtask PRs into the epic branch after the reviewer approves
   and the required checks are green. The epic merges into `main` only on the human's
   explicit command after the human's own testing, with
   `gh pr merge --match-head-commit <tested SHA>`; if the epic touches a protected path,
   the human also approves the PR on GitHub.
6. **After a merge.** The agent verifies the PR is `MERGED`, switches to `main`,
   fast-forwards it, deletes the local branch with `-D` (squash merges leave it unmerged by
   ancestry) and runs `git fetch --prune`. GitHub deletes the remote branch (repository
   setting "Automatically delete head branches").
7. **Auto-merge.** Enabled only after a trial of 5 consecutive PRs in which the reviewer's
   verdict and the human's decision agree (any disagreement restarts the count), and only
   for PRs that touch no protected path.

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
    - .github/workflows/<review-workflow>.yml
  acceptance:
    - The workflow reviews PRs from branches of this repository with the S2 checklist,
      read-only, treating PR content as untrusted data.
    - It reports its result as a check named for the review and cannot approve or merge.
    - The human sets the API key secret and a spending limit. The check is not required
      until S5.
  tier2: none

- id: S4
  title: Add the loop skill and wire the classifier into the gate and CI
  branch: chore/agentic-loop-skill
  skills: [tm-pr-workflow, epic-orchestration]
  depends_on: [S3]
  allowed_paths:
    - .claude/skills/<loop-skill>/**
    - .claude/skills/epic-orchestration/SKILL.md
    - .claude/skills/tm-pr-workflow/SKILL.md
    - .claude/settings.json
    - scripts/pre-push-check.sh
    - .github/workflows/ci.yml
  acceptance:
    - The loop skill covers picking the task with `scripts/check-board.sh --next`,
      implement, local review, fix, gate, push, PR, the retry budget and escalation to the
      human, after-merge cleanup (Decision 6) and the epic merge rule (Decision 5).
    - check-protected-paths.sh runs in the gate and in CI.
    - epic-orchestration and tm-pr-workflow match the Decisions above (today they say no
      agent merges any PR).
    - Deny rules stop the agent from reading other credentials.
  tier2: none

- id: S5
  title: Turn on code owner review and the review check in main's branch protection (human, no PR)
  branch: none
  skills: []
  depends_on: [S4]
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
    - 5 consecutive board tasks are done by the loop with the human merging, and the
      reviewer's verdict agreed with the human's decision on each (Decision 7).
    - Afterwards one small PR documents auto-merge for unprotected paths, and the human
      turns on the repository setting "Allow auto-merge".
  tier2: none
```

## Waves

- S1, S2, S3, S4, S5, S6, strictly one after another (each builds on the previous one, and
  S2 to S4 all edit the same skills and gate).

## Epic-level Tier 2

- The human watches one full loop end to end: next task, reviewer verdict, gate, PR, both
  checks, merge, cleanup.
- The human confirms a protected-path PR is blocked for the agent account.
