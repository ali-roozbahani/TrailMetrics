# Merging the epic into main

The section "Merging the epic into main" of `SKILL.md` moved here and was rewritten on 2026-11-19 for the local-merge flow (`running-an-epic.md`): the subtasks are not PRs, the integration branch is pushed once, and the one PR carries the board commit and the plan's `Status`. The rules are still cited as `epic-orchestration`, "Merging the epic into main".

## Merging the epic into main

The orchestrator reports readiness. The human merges only when all of these hold:

1. Every subtask in the plan is merged into the integration branch (an `Epic-Subtask: <id>` trailer on a merge commit each), or was dropped by a plan change the human approved.
2. The branch includes the latest `main` (strict protection on `main` enforces this; the orchestrator took `main` once before the final review, and if `main` moved after the PR was opened, GitHub's "update branch" or the same local merge, gated again, brings it in).
3. CI is green on the epic PR for every required check, on its current head, and the CI reviewer's findings are answered (`tm-agent-loop`, sections 6 and 7).
4. **The board commit is on the branch.** It is the last commit of the integration branch and part of the epic PR: the epic's record deleted, the records for the follow-ups the subtasks reported, the plan's `Status` set to `done`, with the epic PR's `Board:` line listing them (`tm-pr-workflow`, "Board", rule 5). There is no board PR and no separate human merge for it.
5. The epic-level Tier 2 is done **on the epic PR's head**: the automated tests that cover the epic's end-to-end behavior pass there (condition 3 and the full local gate before the push), the human has done the final smoke check and every human check listed with its reason, and has reviewed the full diff against `main`.

**Merge method (recommendation; the human decides): "Create a merge commit"**, not squash. Each subtask is one merge commit on the branch (`... (subtask <id>)`, with the worker's commits under it), and a merge commit
keeps them in `main`'s history and keeps each one revertible. Squash would collapse the epic into one commit and lose that. The repo allows all three methods. The epic PR title is a valid `type(scope): summary`, because it
appears in the merge commit.

## The orchestrator's part

Once the last subtask is merged: `running-an-epic.md`, step 4 (take `main`, the board commit, the description, one local review and one full gate of the whole branch, one push, the PR, CI, the fixes), and step 5 (the report with the exact merge command
`gh pr merge <n> --merge --match-head-commit <40-character SHA>`, the human checks with their steps, the notes of the escalated local reviews, and "Drift found" with the evidence). The orchestrator never merges the epic PR.

## After the merge

GitHub deletes the remote epic branch. The next run of the orchestrator (`tm-pr-workflow`, "Before starting") prunes the merged local branches, deletes the epic's local branch and run record, and reads `scripts/main-ui-run.sh --status`: a merge of an epic
changes code, so the full UI run is due and runs with an empty queue. Work that the plan names as starting after the epic (a board record with `After: <slug>`) is then free to start.
