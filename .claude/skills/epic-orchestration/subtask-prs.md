# Subtask PRs

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the section "Subtask PRs". The rules are unchanged; they are still cited as `epic-orchestration`, "Subtask PRs".

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
- **Merge**: under Decision 5's conditions (`tm-agent-loop`, "Merge conditions", `merge.md`, with the
  subtask's `allowed_paths` in place of "touches no protected path"). The agent posts its
  merge check (`tm-agent-loop`, "Auto-merge", `merge.md`); when a condition is "no", the human merges.
