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
  (verified 2026-09-29, see "Isolation"), with a default cap of two concurrent subtasks
  to limit build contention. An earlier version of this skill said the gate/hook
  probably broke in worktrees and made sequential the default; that was true before #40.
