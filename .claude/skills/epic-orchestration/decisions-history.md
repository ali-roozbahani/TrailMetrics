# Calls this skill made that the retired workflow doc didn't

Read from `SKILL.md`, "Where this skill made calls the retired workflow doc didn't". The rules are there; this file holds the list.

Recorded so the first real epic can confirm or correct them:

- Branch naming `feature/epic/<slug>` and sibling subtask branches: the retired workflow doc
  named no convention. `ci.yml`'s `feature/**` trigger forces the prefix.
- Protection for epic branches through a single ruleset: the retired workflow doc
  predated required checks on `main` and said nothing about epic branches.
- Subtask merges into the epic branch: the retired workflow doc only forbade merging into
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

- The plan is on `main` (merged by the owner, which is the approval) before the epic branch exists; the epic branch's first commit sets the plan's `Status` to `running`
  so the branch has a diff for the draft PR. Earlier text had the plan itself as the first commit on the epic branch.
- A subtask worker is an `implementer` that the orchestrator integrates (take, review, gate, push, PR, merge). The earlier text had a subtask agent that opened its own PR, which
  the push hook (a recorded local review of the commit), the depth lock on subagents and `tm-agent-loop`, "Never", do not allow.
- The orchestrator merges the subtask PRs it may merge and waits for the human only when nothing else is ready; the earlier text had it wait for the human to merge every wave.
- An epic run does not use the local PR queue, and the queue must be at `DONE` or only waiting for the owner when an epic starts.
- The ruleset pre-flight compares the required check names with the names of the CI jobs; a wrong name had been in the owner's first ruleset.
- The command "run the epic `<slug>`" starts or resumes a run; the state of a run is in GitHub and the plan.
- Open: the local review's base is the merge-base with `origin/main` (`scripts/local-review-prepare.sh`), which makes a subtask's review see the whole epic diff; the skill works around it in the PR description.

