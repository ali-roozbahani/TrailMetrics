# Subtask task file (what a worker is told)

Read from `spawning-subtasks.md`, "What a subtask worker is told". The rules are there; this file holds the template. It replaces the earlier template, which was a standard task prompt with an Epic block for an agent that opened its own PR: a worker is an `implementer` and gets the task as a file with the headings `.claude/agents/implementer.md` defines (`Goal`, `Worktree`, `Allowed paths`, `Contract`, `Read first`, `Tests to run`, `Commit trailer`), and a missing heading is `BLOCKED`.

The orchestrator writes the file with the Write tool at the path `scripts/subagent/worktree.sh create` printed, and starts the worker with the prompt `TASK_FILE: <path>` and nothing else.

```
# Task: <subtask title> (epic <epic-slug>, subtask <id>)

## Goal
<the subtask's title and acceptance criteria, verbatim from the plan>
Out of scope: <the epic's out-of-scope list and anything subtask-specific>
Epic: docs/epics/<epic-slug>.md in your worktree (read it; subtask <id>).
depends_on: <ids>, already merged into the integration branch: <what they added that you use>
Parallel sibling(s) this wave: <ids and their allowed paths>. Do not touch those paths.

## Worktree
Path: <absolute worktree path>
Branch: <chore/wt-name>
Started from: <the subtask's branch> at <sha that create printed>

## Allowed paths
<the plan's allowed_paths, verbatim, one per line; a worker writes only inside them. If the task cannot be done inside them, or the contract has to change:
STATUS: NEEDS_CONTRACT_CHANGE with the file and why. The plan changes only with the owner's approval.>

## Contract
<the interfaces and signatures the plan fixes (the epic's design section), which the worker implements against and does not change>

## Read first
- Skills: tm-pr-workflow (commits), <the code skills of the plan's `skills`>
- Reference implementation: <path>
- <anything else>

## Tests to run
<the module's tests the subtask's tier2 names, through scripts/heavy-run.sh, e.g. `scripts/heavy-run.sh ./gradlew :domain:allTests`>
Red test first, where the plan says so: run the test on the unfixed code, see it fail for the right reason, and put the test's name and its failure message in the commit message.

## Commit trailer
<the attribution trailer the session specifies>
```

The branch the orchestrator integrates is the plan's `branch` (the subtask's branch), never the worktree's `chore/wt-...` branch: `worktree.sh take` brings the commits into it, and `subtask-merge.md` takes it from there. No PR is opened for a subtask.
