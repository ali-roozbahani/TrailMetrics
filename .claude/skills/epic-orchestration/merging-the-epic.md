# Merging the epic into main

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the section "Merging the epic into main". The rules are unchanged; they are still cited as `epic-orchestration`, "Merging the epic into main".

## Merging the epic into main

The orchestrator reports readiness. The human merges only when all of these hold:

1. Every subtask in the plan has its PR merged into the epic branch, or was dropped by a
   plan change the human approved. None is still open.
2. The epic branch includes the latest `main` (strict protection on `main` enforces this;
   sync as in "Lifecycle" step 4, `SKILL.md`).
3. CI is green on the epic PR for every required check, on its current head.
4. **The final board PR is merged into the epic branch, and only then** has the
   orchestrator marked the epic PR ready for review (`gh pr ready <n>`). The final board
   PR is the one board-only PR an epic uses (`tm-pr-workflow` → Board, rule 5). The
   orchestrator opens it into the epic branch after every subtask is merged. It is not a
   plan subtask. It adds `BOARD.md` records for the drift and follow-ups the subtasks
   reported, and deletes the epic's own record if the epic started from one. The
   orchestrator has also filled in the epic PR's description: What changed per subtask
   (with PR links), Skills/docs followed (the union), Tier 1 (the CI result on the epic
   head; no separate local gate is needed, since nothing new is pushed at this point),
   Tier 2 (the plan's epic-level list), any Assumptions and Follow-ups from the subtasks,
   and a `Board:` line listing the records the final board PR added and removed. An epic
   record on the board always points to its plan under `docs/epics/`.
5. The epic-level Tier 2 is done **on the integrated epic branch head**: the automated tests
   that cover the epic's end-to-end behavior on both platforms pass there where such a test
   can exist (condition 3), the human has done the final smoke check and every human check
   listed with its reason, and has reviewed the full diff against `main`.

**Merge method (recommendation; the human decides): "Create a merge commit"**, not
squash. Each subtask is already one conventional commit on the epic branch (`... (#N)`).
A merge commit keeps them in `main`'s history and keeps each one revertible. Squash would
collapse the epic into one commit and lose that. The repo allows all three methods. The
epic PR title is still a valid `type(scope): summary`, because it appears in the merge
commit.
