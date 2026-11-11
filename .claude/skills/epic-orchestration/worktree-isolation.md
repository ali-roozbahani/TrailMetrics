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
