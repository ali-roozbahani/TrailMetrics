# Spawning subtask agents: waves, isolation, what a subtask agent is told

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the section "Spawning subtask agents" (with "Waves", "Isolation" and "What a subtask agent is told"). The rules are unchanged; they are still cited as `epic-orchestration`, "Spawning subtask agents", "Waves", "Isolation" and "What a subtask agent is told".

## Spawning subtask agents

### Waves

A subtask is **ready** when every id in its `depends_on` has its PR **merged into the epic
branch**. An open or approved PR doesn't count: the dependent subtask must branch from
code that is already on the epic branch. The orchestrator spawns a wave, meaning all
ready subtasks whose `allowed_paths` are pairwise disjoint. It then waits for the human to
merge that wave's PRs before it spawns the next one.

Before each wave, check disjointness mechanically, not by eye. For every pair in the
wave, list which tracked files match both glob sets. If any file matches both, the
subtasks can't run in parallel. Tracked files alone can't catch two *new* files at the
same path, so also compare the new file paths the plan names.

### Isolation (read before running two subtasks at once)

Parallel subtasks need separate working trees: two agents on one checkout would switch
branches under each other. The tool for this is the Agent tool with
`isolation: "worktree"`, and **the gate and push hook work in a linked worktree** since #40
(`fix(hooks): resolve the gate pass marker per worktree`):

- `scripts/pre-push-check.sh` writes its pass marker at
  `git rev-parse --path-format=absolute --git-path .pre-push-check-passed`. That is
  `.git/` in the main checkout and `.git/worktrees/<name>/` in a linked worktree. If the
  marker can't be written, the gate fails instead of exiting 0.
- `scripts/claude-hooks/block-git-push.sh` resolves the checkout from the `cwd` in its
  hook input (falling back to its own checkout), then finds that checkout's marker the
  same way, and compares it with that checkout's last commit.

What was verified for the gate and hook in a linked worktree, and what was not yet, is in
`worktree-isolation.md`.

The caution that still applies to parallel worktrees:

- **Resource contention.** Every subtask runs the full gate. Its heavy steps (Gradle
  `detekt`, `lint`, `allTests test`, the Kover coverage report and `koverVerify`,
  `assembleDebug`, plus SwiftLint, the XCFramework build and `xcodebuild` once the diff
  touches `iosApp/` or the shared layer) run unless `scripts/classify-changes.sh` decides
  `light`; that script, not this skill, says which changes are `light`. Each worktree has its own build
  directories and Gradle daemon. Several gates at once on one machine compete for CPU,
  memory and the shared `~/.gradle` cache locks, and can be slower in total than running
  them one after another. Default to **at most two** concurrent subtasks, and fewer when
  more than one of them runs the iOS steps. The human can raise the limit.
  Since the heavy-run lock (`scripts/heavy-run.sh`, which the gate starts itself under) only one
  Gradle or `xcodebuild` run goes at a time on this machine, whoever starts it: the others wait and
  say who they wait for. Parallel subtasks therefore overlap their writing, not their gates, and a
  wait is neither a failure nor a gate attempt.
- **Untracked local files don't come along.** A new worktree has no `local.properties`
  (Android SDK path, `MAPS_API_KEY`) and no `iosApp/TrailMetrics/Secrets.xcconfig`, which
  the iOS build needs. Both are gitignored. The orchestrator copies them from the main
  checkout into each worktree before the subtask runs its gate. Never commit them.
  For an implementer's worktree, `scripts/subagent/worktree.sh create ... --ios --android` puts symbolic
  links to them in the worktree (never read, printed or copied by the script).
- **Sequential in the main checkout is still fine.** It's the right choice when the
  machine can't take concurrent builds or a wave has only one subtask. The ordering,
  scoping and PR-per-subtask rules are the same either way.
- Each worktree is cleaned up after its subtask's PR is opened. The branch lives on in
  the remote.

Never work around the hook (for example by touching the marker by hand, or pushing from a
command the hook's pattern doesn't match). That's a gate bypass, not a fix.

### What a subtask agent is told

The subtask prompt is the standard task prompt template from `tm-pr-workflow` with an
**Epic** block added. Write the block into the prompt itself: a spawned agent starts with
no memory of the planning conversation.

The template, with the Epic block: `subtask-prompt.md`.

Don't pass `model` overrides or extra tools beyond the defaults unless the human asks.
