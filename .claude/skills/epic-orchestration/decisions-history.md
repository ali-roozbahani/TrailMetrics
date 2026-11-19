# Calls this skill made that the retired workflow doc didn't

Read from `SKILL.md`, "Where this skill made calls the retired workflow doc didn't". The rules are there; this file holds the list.

Recorded so the first real epic can confirm or correct them:

- Branch naming `feature/epic/<slug>` and sibling subtask branches: the retired workflow doc
  named no convention. `ci.yml`'s `feature/**` trigger forces the prefix.
- (Superseded 2026-11-19, see below.) Protection for epic branches through a single ruleset: the retired workflow doc
  predated required checks on `main` and said nothing about epic branches.
- (Superseded 2026-11-19, see below.) Subtask merges into the epic branch: the retired workflow doc only forbade merging into
  `main`. Decision 5 of `docs/epics/agentic-dev-loop.md` now lets an agent merge them under
  `tm-agent-loop`'s conditions; the human merges every other subtask PR.
- The plan lives in `docs/epics/<slug>.md`: the retired workflow doc said the plan must be
  reviewed, not where it goes.
- "Ready" means the dependency is merged, not just its PR opened.
- Merge commit for epic → `main`, where every other PR is squash-merged.
- Parallel subtasks run in linked worktrees, which the gate and hook support since #40
  (verified 2026-09-29, see "Isolation", `spawning-subtasks.md`), with a default cap of two concurrent subtasks
  to limit build contention. An earlier version of this skill said the gate/hook
  probably broke in worktrees and made sequential the default; that was true before #40.

Added on 2026-11-19, when the skill was read against the first epic's plan (`running-an-epic.md`):

- The plan is on `main` (merged by the owner, which is the approval) before the integration branch exists. Earlier text had the plan itself as the first commit on the epic branch.
- A subtask worker is an `implementer` that the orchestrator integrates. The earlier text had a subtask agent that opened its own PR, which the push hook (a recorded local review of the commit),
  the depth lock on subagents and `tm-agent-loop`, "Never", do not allow.
- The command "run the epic `<slug>`" starts or resumes a run. An epic run does not use the local PR queue, and the queue must be at `DONE` or only waiting for the owner when an epic starts.
- **The owner's decision of 2026-11-19: a subtask is not a PR, and the first run tests it.** Each subtask is built by its worker, taken in by the orchestrator, reviewed and gated locally, and merged locally into the integration
  branch (a merge commit with the trailer `Epic-Subtask: <id>`). There is no per-subtask PR and no per-subtask CI. When every subtask is merged, the branch is reviewed and gated as a whole, pushed once, and one PR
  `feature/epic/<slug>` into `main` is opened; CI and the CI reviewer run on it, and the owner reviews it and merges it with a merge commit. The reasons the owner gave: the local merge and the local gate are much faster than
  GitHub's CI, so a CI run per subtask mostly buys waiting; one CI run on the final PR is enough and necessary; and the owner is asked to review and merge one PR, not several. It is a **hypothesis**, not a settled fact:
  the first run records the wall time of each local review and gate and of the CI run, what CI or the CI reviewer found that the local checks had not (or the reverse) and every flake (`running-an-epic.md`, "Evidence"),
  and the owner changes his mind if the evidence says he is wrong.
- The ruleset for `feature/epic/*` is not used and may not be active: it requires a pull request and passing checks for every update of the branch, so a fix pushed to the open epic PR after a red CI would be refused. The owner
  deletes it himself; the pre-flight stops the run if one applies; the orchestrator never touches a ruleset. (The first version of the owner's ruleset had also been created with a check name that no job has.)
- The state of a run is the integration branch (a merge commit per subtask, with its trailer) and a run record outside the repository (`~/agent-workspace/epics/<slug>/keep-run.log` and `keep-notes.md`), so the same sentence resumes a stopped run in a
  new session on the same machine. The integration branch is local until the one push; `ci.yml` runs on a push to `feature/epic/**`, so it is not pushed as a backup, and a lost clone loses the unpushed work.
- The epic's board changes and the plan's `Status` are the last commit of the integration branch and travel in the epic PR; there is no final board PR and no extra human merge.
- Open: the local review's base is the merge-base with `origin/main` (`scripts/local-review-prepare.sh`), which makes a subtask's review see the whole epic diff; the skill works around it with a review-scope line in the draft description
  (board record `epic-subtask-review-base`).
