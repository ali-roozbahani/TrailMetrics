# Subagents in the agent loop

Read from `SKILL.md`, "Subagents". The rules are here; `SKILL.md` keeps the pointer. Subagents are tools of
sections 2 and 4 of `SKILL.md` (implementing and the local review), not steps of their own.

The main agent is the orchestrator: it, and only it, integrates. It takes the subagents' commits into
the task branch, runs the local review and the gate, pushes, opens the PR, watches CI, merges and works
the queue (sections 3 to 9). A subagent does none of these: `explorer` has only `Read`, `Grep` and
`Glob`; `implementer` has no tool to start a subagent and a guard hook
(`scripts/subagent/guard.sh`) that refuses a push, `gh`, the queue, the gate and every other script of
the orchestrator and any write outside its allowed paths; `pr-reviewer` is section 4. Whatever a
subagent reports is a claim: the orchestrator reads the diff and the gate decides.

**`explorer`: an open-ended search, or output that would be large** (where is X handled, which files
follow pattern Y, a long log, a sweep over many files). Start it with the question as the prompt and
open the `path:line` evidence it returns before you rely on it. **Not for a targeted lookup** (one
grep, one file, a path you know): do that yourself, because a trivial subagent costs about 20k tokens
against a few hundred in your context.

**Implement yourself, with one implementer, or split: decide from the size of the task, once you have
read the task and the code.** As a starting point (a judgement, not a rule; say what you chose in the
report):

- *Yourself*: the change is a few files in one area (roughly under 5 files or 200 changed lines), or it
  is docs, a skill, a script, or its design is still open. An implementer costs a cold start and a
  context of its own, so a small change is cheaper done directly.
- *One implementer*: a self-contained piece larger than that, whose interfaces and files you can write
  down before it starts. Your context then stays free for the review and the gate.
- *A split, at most 2 implementers writing at the same time*: only when the pieces have **disjoint
  allowed paths** (no file can match both lists; check the globs as `epic-orchestration`, "Spawning
  subtask agents" says, hotspots included: one owner each) and **a contract that you wrote first**:
  the interfaces, signatures and file ownership, committed to the task branch as its own commit before
  any worktree is created, so both start from it. The usual shape is a Kotlin or Swift side and a
  test or UI side that only use the contract. A piece that needs the other's result is not a split:
  take the first, then start the second from the new tip.

The procedure, for each implementer, all from the main clone with the task branch checked out and clean:

1. `scripts/subagent/worktree.sh create <name> --from <task branch> --allow <path>... [--ios]
   [--android]` (the worktree starts from the committed tip; `--ios` and `--android` link the
   git-ignored secrets configs without reading them). It prints the task file's path.
2. Write the task file there with the Write tool, with the headings `implementer.md` defines
   (`Goal`, `Worktree`, `Allowed paths`, `Contract`, `Read first`, `Tests to run`, `Commit trailer`).
   The subagent gets its task through this file and its prompt is only `TASK_FILE: <path>`: a hook
   blocks any command that merely contains the text of a push or of a PR creation, so a task is never
   spelled out in a command (the file is written with the Write tool, not through the shell).
3. Start it (Agent tool, `subagent_type: implementer`), in the background when you have other work, at
   most 2 at a time. While one runs, you do not edit its allowed paths. Its shell is reset to the main
   clone before every call (a real run showed it), so the guard makes it begin every Bash command with
   `cd <worktree> &&`; `implementer.md` says so, and the task file's `Worktree` heading gives the path.
4. On `STATUS: DONE`: `scripts/subagent/worktree.sh take <name>`, one implementer at a time and in its
   own tool call. It brings the commits into the task branch one by one and refuses (changing nothing) a
   commit outside the allowed paths, a merge, uncommitted work or a conflict. Then read the diff of what
   came in. Its test results are its claim; the gate reruns everything.
5. On `BLOCKED` or `NEEDS_CONTRACT_CHANGE`: you decide. Change the contract as a new commit and recreate
   the worktrees that started from the old tip (`remove --force`, `create`), do the piece yourself, or
   drop it. Never widen the allowed paths of a running implementer.
6. `scripts/subagent/worktree.sh remove <name>` once its commits are taken, before the review.
   Before it, and when a run was blocked or ran beside another heavy run, read what the mechanism
   recorded: `scripts/subagent/guard.sh --log` (every call the guard saw, with the subagent's id and
   the input's key names, and each block with its reason and command) and `scripts/heavy-run.sh --log`
   (a `wait` and a `start` after more than 0 s show that a run waited for the lock).

The result is still **one PR with one review and one gate run**: the local review (section 4) and the
gate (section 5) run once on the final HEAD, in the main clone, after every implementer's commits are
in. An implementer's failed test run or blocked call is not an attempt of the gate's retry budget.

**Heavy runs: one at a time on this Mac** (16 GB: two concurrent Gradle or `xcodebuild` runs took twice
as long each and pushed swap up). Every Gradle or `xcodebuild` command goes through
`scripts/heavy-run.sh <command>`; the gate starts itself under it, and an implementer runs its module's
tests that way. A second caller waits for the first and says who it waits for, so a split speeds up the
writing, not the testing. Never start a heavy run around the lock, and do not wait for one with a
foreground `sleep`.

**Nesting.** An implementer has no `Agent` tool and an explorer cannot start anything: nothing below
the orchestrator spawns. (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` in the settings is the owner's
second lock; this skill does not rely on it.)
