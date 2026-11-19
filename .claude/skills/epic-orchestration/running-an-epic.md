# Running an approved epic from one command

Read from `SKILL.md`, "The command". This file is the whole procedure of an epic run: the orchestrator follows it from the owner's sentence to the epic PR that is ready, with no other instruction. The order of the work comes from the plan's `depends_on`, never from the owner at run time. The other files of this skill hold the rules the steps use: `spawning-subtasks.md` (waves, workers), `subtask-prompt.md` (what a worker is given), `subtask-prs.md` (a subtask's PR), `merging-the-epic.md` (the end), `epic-branch-protection.md` (the ruleset check).

## The command

> run the epic `<slug>`

That sentence is all the owner gives. It starts the epic when its branch does not exist and resumes it when it does: the state of a run is in GitHub (the epic PR's status table, the subtask PRs, the branches) and in the plan, never in a session, so the same sentence after a stop continues where the run stopped.

The command means the owner has approved the plan. It does not mean the owner will merge anything on request: the owner's part is listed at the end of this file.

## 1. Before anything is created (all of it automatic; stop only when a check fails)

Stop at the first failed check and report it (what failed, the exact output, what the owner has to do). Nothing is created before all of them pass.

1. `tm-pr-workflow`, "Before starting", and `tm-agent-loop`, "Preconditions": identity, clean tree, `main` pulled, merged branches pruned, the recent runs of `main` (an unacknowledged red run stops the run), the workspace cleaner.
2. **The plan is on `main` and approved.** `docs/epics/<slug>.md` exists on `origin/main`; its "Approved by" line names the owner and a date; its Integration branch is `feature/epic/<slug>`; the board record of the epic (`BOARD.md`) exists and points to the plan. A plan that is only in an open PR, or has `Approved by: pending`, is not approved: report that it waits for the owner and stop.
3. **The queue is not in the way.** `scripts/queue/queue.sh next` prints `DONE`, or `WAIT <slug> #<n> owner` lines only. Any `BUILD`, `FINISH_BUILD`, `PUSH`, `HOLD` or `WAIT ... agent` means queue work is open: finish it first (`tm-agent-loop`, section 9) and report. While the epic runs the queue is not used (see "The queue and the epic").
4. **The plan can be run.** Check the file, by commands, not by eye:
   - the `yaml` block parses by reading: ids are unique, every `depends_on` id exists, there is no cycle, and every subtask has `branch`, `skills`, `allowed_paths`, `acceptance` and `tier2`;
   - every branch is `<feature|bugfix|chore>/<slug>-<subtask-slug>`, the names are distinct, and none exists yet (`git ls-remote --heads origin '<branch>'` prints nothing);
   - every `allowed_paths` entry is a file path or a directory written `dir/**` (it becomes `--allow dir` of `scripts/subagent/worktree.sh`), with no `..` and nothing under `.git`; a glob in any other form is a plan defect: stop;
   - every skill named exists under `.claude/skills/`;
   - **the paths of each wave are disjoint**, checked on the tracked files and on the new paths the plan names:

     ```bash
     python3 -I - <<'EOF'
     import subprocess
     files = subprocess.check_output(['git', 'ls-files'], text=True).split('\n')
     paths = {  # subtask id -> its allowed_paths, copied from the plan
         'S1': ['<path>', '<dir>/**'],
         'S3': ['<path>'],
     }
     waves = [('S1', 'S3')]  # the plan's waves
     def match(g, f): return f.startswith(g[:-2]) if g.endswith('/**') else f == g
     def tracked(s): return {f for f in files if any(match(g, f) for g in paths[s])}
     for wave in waves:
         for i, a in enumerate(wave):
             for b in wave[i + 1:]:
                 print(a, b, sorted(tracked(a) & tracked(b)))
     EOF
     ```

     Any file printed is a plan defect: stop. Also compare the new file paths each subtask of a wave names;
   - the subtasks whose `allowed_paths` include a protected path: `scripts/check-protected-paths.sh --files <path>...` per subtask. Their PRs are the human's to merge (`tm-agent-loop`, "Merge conditions", `merge.md`, condition 6); the report says which.
5. **The ruleset for the epic branches is right** (`epic-branch-protection.md`, "Pre-flight check"). A missing or wrong ruleset is a stop, not a repair: the orchestrator never changes a ruleset.
6. **The epic does not already run.** `git ls-remote --heads origin 'feature/epic/<slug>'`: when it prints a branch, this run is a resume: skip "2. Create the epic branch" and go to "3. The wave loop", whose first step reads the state.

## 2. Create the epic branch and the draft epic PR

1. `git switch -c feature/epic/<slug> origin/main`. The plan is already on `main` (step 2 above), so the branch has no commit of its own; the first commit makes one: it sets the value of the plan's `Status` bullet to `running, started <date>` and changes nothing else, as `chore(epic): start <slug>` with the attribution trailer.
2. Draft the epic PR's description at `~/agent-workspace/pr-body-epic-<slug>.md`: the first line `Title: feat(<scope>): <the epic's one-line summary>` (a valid `type(scope): summary`: it appears in the merge commit), the plan link, and the status table (below). `Board:` line and the other headings are filled at the end (`merging-the-epic.md`).
3. Local review of the commit (`tm-agent-loop`, section 4: `scripts/local-review-prepare.sh <draft>`, the `pr-reviewer`, `scripts/local-review-record-verdict.sh`), the gate (`scripts/pre-push-check.sh`, `light` for a plan line), then `git push -u origin feature/epic/<slug>`. A direct push is allowed once, to create the branch: the ruleset's pull-request rule does not apply to creating it. Every later change reaches the branch through a PR.
4. `gh pr create --draft --base main --head feature/epic/<slug> --title "<title>" --body-file <body>` (the body file is `scripts/set-pr-body.sh --print-body <draft>`; the PR title is the draft's `Title:` line). The epic PR is the human's to merge (`tm-agent-loop`, "Never").

**The status table** is the epic's live state, in the epic PR's description, one row per subtask, written by the orchestrator and set with `scripts/set-pr-body.sh <epic PR> <draft>` after every change:

```
| Subtask | Branch | Wave | State | PR | Merged by |
|---|---|---|---|---|---|
| S1 | bugfix/<slug>-<subtask-slug> | 1 | merged | #<n> | agent |
| S2 | feature/<slug>-<subtask-slug> | 2 | waiting-human | #<n> | |
| S3 | chore/<slug>-<subtask-slug> | 1 | building | | |
| S4 | feature/<slug>-<subtask-slug> | 3 | blocked-by S2 | | |
```

States: `blocked-by <ids>`, `ready`, `building`, `integrating` (the worker's commits are taken in and the review or the gate runs), `in-ci`, `waiting-human` (the Merge check says why), `merged`, `dropped` (only with the owner's approval of a plan change). The plan file is never edited for status.

## 3. The wave loop

Repeat until every subtask is `merged`. Each pass starts by reading the state again, from GitHub and not from memory:

```bash
git fetch origin --prune
gh pr list --base feature/epic/<slug> --state all --json number,state,headRefName,mergedAt,mergeStateStatus
```

1. **Ready** subtasks: every id in `depends_on` has its PR merged into the epic branch (`spawning-subtasks.md`, "Waves"), and the subtask has no open PR or live worker. A subtask whose PR is open and not merged is `in-ci` or `waiting-human`, not ready.
2. **A wave** is the ready subtasks whose `allowed_paths` are pairwise disjoint (the check of step 1.4 again on the ready set), at most 2 at a time (`spawning-subtasks.md`, "Isolation"). When more are ready than the cap or the disjointness allows, the plan's order of ids decides which go first; the rest wait for the next pass. No instruction from the owner is needed or taken for this.
3. **For each subtask of the wave** (`spawning-subtasks.md`, "Workers"): create its branch from `origin/feature/epic/<slug>`, start its `implementer` in a worktree, take the commits in, run the local review and the gate, push, open the PR against the epic branch, watch CI, then merge or hand over (`subtask-prs.md`). The PRs of one wave are integrated one at a time (heavy runs are serialized by `scripts/heavy-run.sh` whatever the waves say); the second worker keeps writing while the first is integrated.
4. **Merging a subtask PR** follows `tm-agent-loop`, "Merge conditions" (`merge.md`), with condition 6 replaced by the plan's `allowed_paths` and with the read of `main` skipped: the base is the epic branch. All six "yes": merge with `gh pr merge <n> --squash --match-head-commit <sha> --subject "<title> (#<n>)" --body ""`, post the Merge check, set the row to `merged` with `Merged by: agent`. Any "no": post the Merge check, set the row to `waiting-human`, and go on with the work that does not depend on it (step 5).
5. **When a human has to merge**: the orchestrator does not stop while other work is ready. When nothing else is ready or running, it waits for the PRs in `waiting-human` with one background command that exits at the first change, and acts on it:

   ```bash
   # PRS="<n> <n> ..." the waiting subtask PRs; run with run_in_background, timeout 10 minutes, and run it again until the wait below runs out
   while true; do
     for n in $PRS; do
       s="$(gh pr view "$n" --json state --jq .state)"
       [ "$s" != OPEN ] && echo "$s #$n" && exit 0
     done
     sleep 60
   done
   ```

   `MERGED #<n>`: the row is `merged` (`Merged by: owner`), start the next pass. `CLOSED #<n>`: the owner dropped it: a plan defect: stop and report. The wait for the owner ends after 180 minutes in total (the queue's owner wait): the run then ends with the report, which names each PR it waits for, with its merge command and the full 40-character head SHA, and the resume sentence. The same command resumes it.
6. **A subtask PR that is behind the epic branch** because a sibling merged first (strict): `git merge origin/feature/epic/<slug> --no-edit` into the subtask branch (its own tool call), review, gate, push, comment (`subtask-prs.md`). A merge conflict means two subtasks' `allowed_paths` overlapped: a plan defect: stop and report.
7. **Keeping up with `main`** (`SKILL.md`, "Lifecycle", step 4) is done between waves, only when `main` has changed a file that matches an `allowed_paths` of a subtask not yet merged, and once more before the epic PR is made ready (`merging-the-epic.md`). A sync PR (`chore/<slug>-sync-main`) is merged by the agent only when every file `main` changed since the epic branch's base is unprotected; otherwise it is the human's.
8. **A stop that belongs to the plan** (the plan's "Re-plan trigger", a subtask that needs a path outside its `allowed_paths`, a worker's `NEEDS_CONTRACT_CHANGE`, two retries of the gate used up, a red CI after its one re-run): stop the run, leave the rows as they are, and report what the owner has to decide. The plan changes only with the owner's approval, as a `chore(epic)` commit through a PR.

## 4. The end

When every row is `merged`:

1. The final board PR (`tm-pr-workflow`, "Board", rule 5): from the epic branch, `chore/<slug>-board`, into the epic branch. It carries what the plan says (the epic record deleted in its own commit, the `After:` line, the records for the drift and follow-ups the subtasks reported in their descriptions, the plan's `Status` set to `done`). The plan is under `/docs/epics/`, a protected path, so the human merges this PR: it is the one more human merge of every epic. Wait for it as in step 5.
2. Sync with `main` if it moved (step 7), then fill in the epic PR's description (`merging-the-epic.md`), `gh pr ready <n>`, and wait for CI on the epic PR's current head (`scripts/wait-for-checks.sh`).
3. The report (`tm-agent-loop`, "Report"), with a "Drift found" part, as the skill says: which assumption of this skill was confirmed or corrected by the run (the worktree `cwd`, the ruleset, the merge conditions, the status table, the waits), each with the evidence. Then stop: the epic PR is the owner's to merge.

## The queue and the epic

An epic run does not use the local PR queue (`scripts/queue/queue.sh`): the queue knows only PRs against `main`. A subtask PR is not an entry; it is tracked by the status table and the plan. `scripts/queue/watch-prs.sh` lists open PRs of every base and is not used to wait for an epic. The heavy-run lock is shared by everything: every gate and every worker's test run goes through `scripts/heavy-run.sh`, and a wait for it is neither a failure nor a gate attempt. While the epic runs, no other work starts in the session: a follow-up found goes into a subtask's PR description and, at the end, into the final board PR. After the epic is merged, the next run starts the queue again. A run of the queue that finds an open epic branch does not touch it.

## What the owner does

- **Before the run:** the ruleset for `feature/epic/*` has the four required checks with the names of the CI jobs (the pre-flight says if not; the owner edits it, the orchestrator never does); the plan is merged into `main` with its approval line; the machine is on, logged in as `peter-christofer-bot`, with the iOS secrets config and `local.properties` in the clone.
- **During the run:** merge a subtask PR when its Merge check says "no" (a protected path, or a reviewer verdict other than a bare `APPROVE`); merge the final board PR; answer a stop that belongs to the plan. Nothing else.
- **At the end:** do the human checks of the plan's epic-level Tier 2 on the integrated epic branch, review the full diff, and merge the epic PR with a merge commit (`merging-the-epic.md`).
