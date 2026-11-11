# Subtask prompt template

Read from `SKILL.md`, "What a subtask agent is told". The rules are there; this file holds the template.

```
Task: <subtask title>

Epic:
- Epic plan: docs/epics/<epic-slug>.md on origin/feature/epic/<epic-slug> (read it; subtask <id>)
- Base branch: feature/epic/<epic-slug>. Branch from origin/feature/epic/<epic-slug>,
  and open the PR with --base feature/epic/<epic-slug>, NOT main.
- depends_on: <ids>, already merged into the base branch: <what they added that you use>
- allowed_paths (the only files you may create, modify or delete):
    <globs, verbatim from the plan>
- Parallel sibling(s): <ids + their allowed_paths>. Do not touch those paths.
- If the task can't be done inside allowed_paths, stop and report which file and why.
  Do not edit it. The plan changes only with human approval.

Context:
- Skills to load: tm-pr-workflow, <code skills from the plan>
- Reference implementation: <path>
- <anything else>

Scope:
- Acceptance criteria: <verbatim from the plan>
- Out of scope: <epic's out-of-scope list + anything subtask-specific>

Branch: <branch from the plan>
```
