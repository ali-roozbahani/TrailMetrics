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
  push, `gh`, the orchestrator's scripts and a `cd` out of the worktree, and refuses a worktree without the
  record (from the main clone it judges by what the call names, see the runs below).
- A linked worktree's git directory has the layout `tm-pr-review`'s `GIT_HEAD_MISMATCH` check reads
  (`.git` file with `gitdir:`, `HEAD`, `commondir`, `refs/heads` or `packed-refs` in the common directory).

Verified on 2026-11-13 by three real `implementer` runs in throwaway worktrees (and one `explorer` run):
- The front-matter `hooks:` of a project subagent fire for its tool calls, and a hook's message reaches the
  subagent, which reports it.
- The `cwd` a subagent's hook receives is the main session's directory, the main clone, on every call: the
  shell is reset to it before each Bash call, so a `cd` does not last, and a Write is judged with it too. The
  guard therefore judges by what a call names (the absolute target path, a leading `cd <worktree>`), not by
  `cwd`; the first design, which trusted `cwd`, refused every call and the implementer could not start.
- With the guard that judges by target: an allowed Write, a refused Write outside the allowed paths, a refused
  orchestrator script and a commit in the worktree all behaved as designed (STATUS: DONE).
- `explorer` starts on `claude-haiku-5-5` and answers (about 17k tokens for a trivial question).

Not yet verified:
- What the hooks of `.claude/settings.json` (the push and review hooks) receive for a subagent: they run for it
  per the documentation, with `agent_id` and `agent_type`; not observed here. The same holds for `agent_id` in a
  front-matter hook's input (the guard does not use it).
- `worktree.sh take` and `remove` on a real implementer's commits: only the self-tests ran them.
- That a reviewer started from a worktree can `Read` the common git directory (it may need
  `--add-dir`, `tm-pr-review`, "Orchestrator's part", step 2).
