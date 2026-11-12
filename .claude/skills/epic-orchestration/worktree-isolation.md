# Parallel worktrees: what was verified

Read from `SKILL.md`, "Isolation". The rules are there; this file holds the record of what was verified and what was not.

Verified on 2026-09-29 against `main` at `09a86a8`:
- In a throwaway linked worktree, the full gate passed (exit 0) and wrote the marker under
  `.git/worktrees/<name>/`.
- The hook, fed a push command with that worktree as `cwd`, allowed it (exit 0).
- With a fresh worktree that had no marker as `cwd`, it blocked (exit 2).

Not yet verified: a real push from an Agent-tool worktree session, i.e. that the hook
input's `cwd` there is the worktree. The first epic that runs parallel subtasks should
confirm it and report under "Drift found" if it isn't.

Added on 2026-11-12 with the implementer subagent (`scripts/subagent/`, `.claude/agents/implementer.md`).

Verified (self-tests of `worktree.sh` and `guard.sh`, a scratch repository, no real subagent):
- `worktree.sh create` makes the worktree on a new local branch from the chosen branch's tip, records the
  allowed paths in the worktree's own git directory and links the secrets configs without reading them;
  `take` cherry-picks the commits one at a time, refuses a commit outside the allowed paths, a merge, an
  uncommitted worktree and a wrong branch, and undoes a conflicting take; `remove` cleans up.
- The guard, fed hook-shaped JSON with the worktree as `cwd`, refuses writes outside the allowed paths, a
  push, `gh`, the orchestrator's scripts and a `cd` out of the worktree, and refuses every call from the
  main clone or a worktree without the record.
- A linked worktree's git directory has the layout `tm-pr-review`'s `GIT_HEAD_MISMATCH` check reads
  (`.git` file with `gitdir:`, `HEAD`, `commondir`, `refs/heads` or `packed-refs` in the common directory).

Not yet verified (needs a real implementer run; the first one should report under "Drift found"):
- That Claude Code runs the front-matter `hooks:` of a project subagent for its tool calls (the
  documentation says it does after the workspace trust dialog).
- What the hooks of `.claude/settings.json` (the push and review hooks) receive for a subagent working in
  a worktree: the documentation says `cwd` is the worktree root after the subagent enters it and that
  `agent_id` and `agent_type` are set, but no run was observed here.
- That a `cd` of the implementer into its worktree persists across its Bash calls as the guard assumes.
- That a reviewer started from a worktree can `Read` the common git directory (it may need
  `--add-dir`, `tm-pr-review`, "Orchestrator's part", step 2).
