# Subtask PRs

The section "Subtask PRs" of `SKILL.md` moved here and was rewritten on 2026-11-19 with `running-an-epic.md`: the orchestrator opens and merges every subtask PR (a worker only writes commits), and the review scope, the wait for the human and the status table are new. The rules not named here are unchanged; they are still cited as `epic-orchestration`, "Subtask PRs".

## Subtask PRs

Everything in `tm-pr-workflow` applies. Only these parts change:

- **Base**: the subtask's branch is made with `git switch -c <branch> origin/feature/epic/<slug>` (after `git fetch origin`; `spawning-subtasks.md`, "Workers"),
  and the PR with `gh pr create --base feature/epic/<slug>`. A subtask PR against `main` is wrong:
  close it and reopen it against the epic branch.
- **Scope check before push**: `git diff --name-only origin/feature/epic/<slug>...HEAD`
  must list only files matching `allowed_paths` (`worktree.sh take` already refuses a worker's commit outside them; this is the orchestrator's own check). Put the output in the PR under
  "What changed".
- **Review scope**: `scripts/local-review-prepare.sh` and the gate compare with the merge-base with `origin/main`, so on a subtask branch the local reviewer sees the whole epic
  diff so far, earlier subtasks included. The draft PR description says in "What changed" that the scope of the review is the commits of this subtask,
  `origin/feature/epic/<slug>..HEAD`, and lists its `allowed_paths`; the reviewer judges those commits against the subtask's acceptance. The CI reviewer
  compares with the PR's base (the epic branch tip) and needs no such line, but it also reads the `allowed_paths` from the description (`tm-pr-review`, "Inputs"). A `--base` option of the
  prepare script would remove the workaround: it is a script change, left to the owner (board: `epic-subtask-review-base`).
- **Gate scope**: `pre-push-check.sh` diffs against the merge-base with `origin/main`, not
  the epic branch. Once the first subtask touching the shared layer is merged, **every** later subtask runs
  the iOS steps, including an Android-only one, because the epic's shared changes are in
  its diff. That's expected: it builds iOS against the integrated shared layer. Report it
  in Tier 1 rather than calling it spurious. The protected-path check of `tm-agent-loop`, section 3, takes `--base "$(git merge-base HEAD origin/feature/epic/<slug>)"` here.
- **Out of date with the epic branch** (a sibling merged first, and strict blocks the
  merge): `git merge origin/feature/epic/<slug>` into the subtask branch (not rebase plus
  force-push, in its own tool call), re-run the review and the gate, push, and comment on the PR. That's a new commit, not a
  retry-budget attempt. A merge conflict means two subtasks' `allowed_paths` overlapped.
  Stop and report it as a plan defect. (`scripts/queue/update-branch.sh` is for the queue's PRs against `main` and is not used.)
- **PR description**: the four `tm-pr-workflow` headings, plus a first line
  `Epic: <slug> · Subtask <id> · depends_on: <ids>` linking the plan and the epic PR, and a line
  `allowed_paths: <the plan's list>` (the CI reviewer reads it). Under Tier 2, give the subtask's `tier2` line from the plan, with the tests' real names.
  The human may postpone a human check it lists to the epic-level Tier 2, which is their call.
- **Title**: `type(scope): summary` as usual. Subtask PRs squash-merge into the epic
  branch, so each subtask becomes one conventional commit there.
- **Board**: a subtask never edits `BOARD.md`, because parallel siblings would conflict
  on it. It lists drift and follow-ups in its PR description only, with
  `Board: no changes` (`tm-pr-workflow` → Board, rule 5). The orchestrator collects them for the final board PR.
- **CI and the verdict**: after the push, `tm-agent-loop`, section 6 (`watching-ci.md`): the reviewer first (`scripts/wait-for-checks.sh --review-first <PR>`), then the rest.
  The reviewer's verdict reads as for any PR; a verdict that is not a bare `APPROVE` makes condition 4 "no".
- **Merge**: under Decision 5's conditions (`tm-agent-loop`, "Merge conditions", `merge.md`, with the
  subtask's `allowed_paths` in place of "touches no protected path"; the read of `main`
  before a merge belongs to the queue and is not taken for a PR into the epic branch). The agent posts its
  merge check (`tm-agent-loop`, "Auto-merge", `merge.md`) on every subtask PR; all six "yes": it merges and sets the status table row to `merged`; when a condition is "no", the row is
  `waiting-human`, the human merges, and the orchestrator goes on with other ready work (`running-an-epic.md`, step 3.5).
- **After the merge**: `git fetch origin`; the dependent subtasks of the plan become ready; the subtask's local branch and worktree record are cleaned as `tm-agent-loop`, "After-merge cleanup".
