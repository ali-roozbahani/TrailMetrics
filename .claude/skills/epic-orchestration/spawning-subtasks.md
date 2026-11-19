# Spawning subtask workers: waves, workers, isolation, what a worker is told

The section "Spawning subtask agents" of `SKILL.md` moved here, with "Waves", "Isolation" and "What a subtask agent is told", and was rewritten on 2026-11-19 for the run of `running-an-epic.md`: a subtask worker is an `implementer` that the orchestrator integrates, not an agent that opens its own PR. The sections keep their names where they existed, so a reference to `epic-orchestration`, "Waves" or "Isolation" is found here; "Workers" is new.

## Spawning subtask workers

### Waves

A subtask is **ready** when every id in its `depends_on` has its PR **merged into the epic
branch**. An open or approved PR doesn't count: the dependent subtask must branch from
code that is already on the epic branch. The orchestrator starts a wave, meaning all
ready subtasks whose `allowed_paths` are pairwise disjoint, at most 2 at a time. It integrates the
wave's PRs, merges those it may merge (`tm-agent-loop`, "Merge conditions", `merge.md`), and for the ones
only the human may merge it goes on with whatever else is ready, and waits only when nothing else is
(`running-an-epic.md`, step 3). The next wave starts as soon as its `depends_on` are merged, not when a
whole wave is.

Before each wave, check disjointness mechanically, not by eye. For every pair in the
wave, list which tracked files match both glob sets (the snippet of `running-an-epic.md`, step 1.4). If any file matches both, the
subtasks can't run in parallel. Tracked files alone can't catch two *new* files at the
same path, so also compare the new file paths the plan names.

### Workers

A worker is the `implementer` subagent (`.claude/agents/implementer.md`, `tm-agent-loop`, "Subagents"). One worker per subtask; the orchestrator
integrates its commits. For each subtask of a wave, from the main clone with a clean tree:

1. `git fetch origin && git switch -c <the subtask's branch> origin/feature/epic/<slug>`. The branch is the plan's `branch`; it stays checked out in the main clone
   until the worker's commits are taken.
2. `scripts/subagent/worktree.sh create <name> --from <the subtask's branch> --allow <path>... [--ios] [--android]`, with `<name>` the subtask id in lower case
   (`s2`) and one `--allow` per `allowed_paths` entry: a file path as it is, `dir/**` as `dir`. `--ios` and `--android` as the subtask's tests need them (the links
   to the git-ignored iOS secrets config and `local.properties`, never read or copied; `worktree.sh` header). It prints the task file's path.
3. Write the task file there with the Write tool (`subtask-prompt.md`), start the worker (Agent tool, `subagent_type: implementer`, prompt `TASK_FILE: <path>`),
   in the background when the wave has a second worker or other work waits.
4. On `STATUS: DONE`: `scripts/subagent/worktree.sh take <name>` (one at a time, in its own tool call, with the subtask's branch checked out and clean:
   to take the second worker's commits, `git switch` to its branch first). Read the diff of what came in against the plan's acceptance. The worker's
   test results are its claim; the gate reruns everything.
5. On `BLOCKED` or `NEEDS_CONTRACT_CHANGE`: the orchestrator decides within the plan. A file outside `allowed_paths`, or a change of the contract the plan
   fixes, is a plan defect: stop and report (`running-an-epic.md`, step 3.8). The orchestrator never widens a worker's allowed paths.
6. `scripts/subagent/worktree.sh remove <name>` once the commits are taken, then the review and the gate (`subtask-prs.md`).

A subtask that is small (a few files, a plan line) may be done by the orchestrator itself, as `tm-agent-loop`, "Subagents" says for any task; it
still stays inside `allowed_paths`, and the status table says nothing different.

### Isolation (read before running two workers at once)

Parallel workers need separate working trees: two agents on one checkout would switch branches under each other. The worktrees are those of
`scripts/subagent/worktree.sh`, under `<main clone>/.claude/worktrees/<name>`, each on its own local branch `chore/wt-<name>` that is never pushed. The
integration (take, review, gate, push, PR) happens in the main clone, so **the gate and the push hook never run in a worktree** for an epic, which removes
the question of the pass marker per worktree (it is verified, see `worktree-isolation.md`, and not relied on here).

- **Resource contention.** Every subtask runs the full gate. Its heavy steps (Gradle
  `detekt`, `lint`, `allTests test`, the Kover coverage report and `koverVerify`,
  `assembleDebug`, plus SwiftLint, the XCFramework build and `xcodebuild` once the diff
  touches `iosApp/` or the shared layer) run unless `scripts/classify-changes.sh` decides
  `light`; that script, not this skill, says which changes are `light`. Since the heavy-run lock (`scripts/heavy-run.sh`, which the gate starts itself under)
  only one Gradle or `xcodebuild` run goes at a time on this machine, whoever starts it: the others wait and say who they wait for. Workers therefore
  overlap their writing, not their gates or their test runs, and a wait is neither a failure nor a gate attempt. The cap is **2 concurrent workers**; the human
  can raise it.
- **Untracked local files don't come along.** `--ios` and `--android` of `worktree.sh create` put symbolic links to the iOS secrets config and `local.properties` in
  the worktree. Never read, print, copy or commit them. A gate in the main clone has the real files.
- **Sequential is still fine** when a wave has one subtask or the machine cannot take two. The ordering, scoping and PR-per-subtask rules are the same either way.
- A worktree is removed after its commits are taken. The subtask's branch lives on until its PR is merged; GitHub deletes the remote branch.

Never work around a hook (for example by touching the gate marker by hand, or pushing from a command the hook's pattern doesn't match). That's a gate bypass, not a fix.

### What a subtask worker is told

The worker's prompt is one line, `TASK_FILE: <path>`; the task is the file (`subtask-prompt.md`): the subtask's title, its worktree, its `allowed_paths` verbatim, its acceptance
verbatim, the contract, what to read, the tests to run and the commit trailer. Write the epic block into the file itself: a worker starts with no memory of the
planning conversation, and a hook blocks any command that merely contains the text of a push or of a PR creation, so a task is never spelled out in a command.

Don't pass `model` overrides or extra tools beyond the defaults unless the human asks.
