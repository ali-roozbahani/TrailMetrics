# Running an approved epic from one command

Read from `SKILL.md`, "The command". This file is the whole procedure of an epic run: the orchestrator follows it from the owner's sentence to the epic PR that is open, green and waiting for the owner, with no other instruction. The order of the work comes from the plan's `depends_on`, never from the owner at run time. The other files of this skill hold the rules the steps use: `spawning-subtasks.md` (waves, workers), `subtask-prompt.md` (what a worker is given), `subtask-merge.md` (integrating one subtask), `merging-the-epic.md` (the end), `epic-branch-protection.md` (the ruleset check).

**The decision this flow rests on (the owner, 2026-11-19), and a hypothesis:** a subtask is not a PR. Each is built by its worker, taken in, reviewed and gated locally, and merged locally into the integration branch. The branch is pushed once, and one PR into `main` gets CI and the CI reviewer. The first run tests the decision: see "Evidence".

## The command

> run the epic `<slug>`

That sentence is all the owner gives. It starts the epic when its integration branch does not exist and resumes it when it does. The state of a run is in two places, so the same sentence continues a stopped run, also in a new session on the same machine: the **integration branch** (`feature/epic/<slug>`, local until step 5) and the **run record** (below). The branch says which subtasks are merged; the run record says when, how long, and what was noted.

The command means the owner has approved the plan. The owner's part is listed at the end of this file.

**A decision can ride in the sentence.** When a run stopped for a decision only the owner can make, the owner gives it by saying the sentence again with the decision after it, in his own words, for example: "run the epic `<slug>`, S4: accept the escalation, the test changes are in the plan", or "S2: fix the finding about X as follows ...", or "S4: drop it, change the plan to ...". The same words may be given in the first sentence ahead of a stop, for a subtask and a reason the owner already expects. "The owner's decisions at a stop" below says how the run records and applies it.

## The run record

A directory outside the repository, `~/agent-workspace/epics/<slug>/`, made by the orchestrator, with these files (the draft descriptions of `subtask-merge.md` and step 4 are kept there too). Their names start with `keep-` so the workspace cleaner (`tm-agent-loop`, "Preconditions") does not delete them:

- `keep-run.log`: one tab-separated line per event, appended with `printf`: UTC time, subtask id (or `-`), event, detail. Events: `start`, `ready`, `worker-start`, `worker-done`, `take`, `review-start`, `review-end` (verdict, findings), `gate-start`, `gate-end` (exit code), `merged` (the merge commit), `stop` (reason), `final-review-start`, `final-review-end`, `final-gate-start`, `final-gate-end`, `pushed`, `pr-opened` (number), `ci-start`, `ci-end` (conclusion per job), `ci-fix`, `flake`. The times are wall-clock; the seconds of a review or a gate are the difference of its two lines. This log is the data of "Evidence".
- `keep-decisions.md`: the owner's decisions, one block each, appended by the orchestrator when it reads them (see "The owner's decisions at a stop"): the time, the subtask id, the reviewed commit the decision is about, the reasons it covers, the owner's words, and what the run did with it.
- `keep-failed-<label>-<time>.log`: the device state of a verification run that did not end as expected (an emulator or device run whose session never ended, a notification left behind, a process that died), kept by `scripts/epic/keep-device-log.sh <slug> <label>` as the first command after that run, before the next run, before `logcat -c` and before the app is force-stopped. The next run clears the device log, and one log of a failure is worth more than the runs that pass after it; the run record names each kept file next to the run's line in `keep-run.log` (`stop` or a note).
- `keep-notes.md`: what the subtasks found and the orchestrator must not lose: drift, follow-ups (each with the reason a `BOARD.md` record or a fix is right), the notes of a local review that escalated (`ESCALATE_TO_HUMAN` with no blocking finding), and every `[important]` finding with its disposition. The epic PR's description and the board commit are written from it.

A run record that is lost does not lose the work (the branch has it); it loses the times and the notes, and the report says so.

## 1. Before anything is created (all of it automatic; stop only when a check fails)

Stop at the first failed check and report it (what failed, the exact output, what the owner has to do). Nothing is created before all of them pass.

1. `tm-pr-workflow`, "Before starting", and `tm-agent-loop`, "Preconditions": identity, clean tree, `main` pulled, merged branches pruned, the recent runs of `main` (an unacknowledged red run stops the run), the workspace cleaner.
2. **The plan is on `main` and approved.** `docs/epics/<slug>.md` exists on `origin/main`; its "Approved by" line names the owner and a date; its Integration branch is `feature/epic/<slug>`; the board record of the epic exists and points to the plan. A plan that is only in an open PR, or has `Approved by: pending`, is not approved: report that it waits for the owner and stop.
3. **The queue is not in the way.** `scripts/queue/queue.sh next` prints `DONE`, or `WAIT <slug> #<n> owner` lines only. Any `BUILD`, `FINISH_BUILD`, `PUSH`, `HOLD` or `WAIT ... agent` means queue work is open: finish it first (`tm-agent-loop`, section 9) and report. While the epic runs the queue is not used (see "The queue and the epic").
4. **The plan can be run.** Check the file, by commands, not by eye:
   - the `yaml` block parses by reading: ids are unique, every `depends_on` id exists, there is no cycle, and every subtask has `branch`, `skills`, `allowed_paths`, `acceptance` and `tier2`;
   - every branch is `<feature|bugfix|chore>/<slug>-<subtask-slug>`, the names are distinct, and none exists locally or on `origin` yet;
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

     Any file printed is a plan defect: stop. Also compare the new file paths each subtask of a wave names.
5. **No ruleset blocks the epic PR's fixes** (`epic-branch-protection.md`, "Pre-flight check"). An active ruleset that applies to `feature/epic/<slug>` and requires a pull request or status checks is a stop: the owner deletes it. The orchestrator never changes a ruleset.
6. **The epic does not already run.** `git branch --list 'feature/epic/<slug>'` and `git ls-remote --heads origin 'feature/epic/<slug>'`: a local branch means this run is a resume (skip step 2, read the state in step 3.1); a branch on `origin` and none locally is a stop (someone pushed it; the orchestrator does not guess).

## 2. Create the integration branch and the run record

1. `git switch -c feature/epic/<slug> origin/main`. The branch is local, has no commit of its own yet, and is not pushed.
2. `mkdir -p ~/agent-workspace/epics/<slug>` and `keep-run.log`, `keep-notes.md` and `keep-decisions.md`; append the `start` line.

## 3. The wave loop

Repeat until every subtask is merged. Each pass starts by reading the state again, not by remembering it:

```bash
git branch --list '<type>/<slug>-*'                  # subtask branches in flight
scripts/subagent/worktree.sh list                    # workers' worktrees
git log origin/main..feature/epic/<slug> --grep='^Epic-Subtask: ' --format='%h %s%n%b'   # merged subtasks (the trailer)
tail -n 20 ~/agent-workspace/epics/<slug>/keep-run.log
```

1. **Merged** subtasks are the ones whose id is in an `Epic-Subtask:` trailer on the integration branch. **Ready** subtasks have every `depends_on` id merged, no live branch and no live worker. A subtask with a branch but no merge is in flight: if its worktree has commits not taken, `take` them; if its branch has commits, continue at the integration steps of `subtask-merge.md`; if it has neither, start its worker again.
2. **A wave** is the ready subtasks whose `allowed_paths` are pairwise disjoint (the check of step 1.4 again on the ready set), at most 2 workers writing at a time (`spawning-subtasks.md`, "Isolation"). When more are ready than the cap or the disjointness allows, the plan's order of ids decides which go first; the rest wait for the next pass. No instruction from the owner is needed or taken for this.
3. **Per subtask** (`spawning-subtasks.md`, "Workers"; `subtask-merge.md`): create its branch from the integration branch, start its `implementer` in a worktree, take the commits in, then **integrate it**: bring the branch up to the integration tip, scope check, local review, gate, local merge. Integrations are **one at a time** (the heavy-run lock serializes gates anyway, and the merge result must equal the gated tree); the second worker keeps writing while the first is integrated.
4. **A subtask that does not pass is stopped, and the run goes on without it.** A `[blocking]` finding still there after 2 review fix attempts, a gate that stays red after its 2 fix attempts (`tm-pr-workflow`, "Retry budget"), or a local review that escalates for a reason the plan does not name (`subtask-merge.md`, step 5) is a stop of that subtask: log `stop` with the reasons, leave its branch as it is, and mark it stopped. The run continues with every subtask that does not depend on it, directly or through another; when nothing else is ready or in flight the run ends with the report, which says for each stopped subtask what the owner has to decide. The owner decides as "The owner's decisions at a stop" says.
5. **A stop that belongs to the plan** (the plan's "Re-plan trigger", a subtask that needs a path outside its `allowed_paths`, a worker's `NEEDS_CONTRACT_CHANGE`, a flaw in the plan found while building): the same, for the subtasks that depend on the flaw. The plan changes only with the owner's approval, as a `chore(epic)` commit on the integration branch that travels in the epic PR.
6. **Nothing in the loop waits for a human.** The orchestrator merges each subtask locally; there is no subtask PR to merge, no Merge check and no CI to wait for before the next subtask. The loop ends when the last subtask is merged.

## The owner's decisions at a stop

A stop is resolved by a decision of the owner that reaches the run in the sentence, is recorded, and is applied to the stopped subtask only, once. Without this a resume would run the local review of the same commit again, get the same escalation, and stop again.

1. **How it reaches the run.** The owner says the command again with the decision after it (above). On a resume the orchestrator reads the words after the slug as decisions, one per subtask id, before it does anything else.
2. **Where it is recorded.** Appended to `keep-decisions.md` as a block: the time, the subtask id, the head commit of the subtask branch that the stop was about (`git rev-parse <branch>`), the reasons the decision covers (copied from the stop's `keep-run.log` line), the owner's words, and what the run did. A decision that the orchestrator cannot tie to a stopped subtask, a commit and its reasons is not applied: it is quoted back in the report and the run asks for it to be given again with the missing part.
3. **What it can be.** `accept`: the subtask is merged as it is, the reasons go to the epic PR's "For the owner" part. `fix: <instruction>`: the instruction goes to the subtask's worker (or is done by the orchestrator within `allowed_paths`) as a new commit, which is reviewed and gated like any (the decision covers the earlier commit only). `drop` or a plan change: the plan is changed with a `chore(epic)` commit on the integration branch, in the owner's words, and the dependent subtasks follow the changed plan. `stop`: the run ends and nothing is merged.
4. **What it covers: that subtask, that commit, those reasons, once.** It is applied only when the subtask's head is the commit recorded and the reasons of its review (the recorded report of that commit, `scripts/local-review-gate.sh check <sha>`, or the report of a new run of the same commit) are all among the reasons the decision covers. A new commit, or a reason that is not covered, is a new stop with its own report. A decision for one subtask never applies to another, and an applied decision is marked `applied` in its block so that it is not applied again.
5. **A decision given ahead** (in the first sentence) is recorded the same way, with the commit left open: it covers the named subtask and the reasons it names, for the first commit of that subtask that stops for exactly those reasons. It is the owner's way to say, before he leaves the machine, that a stop he can predict (for example S4's deleted test the plan names) may go on.
6. **Nothing else resumes a stop.** The orchestrator never decides for the owner, never re-runs a review hoping for a different verdict and never rewrites a subtask to get past a finding that its acceptance does not call for.

## 4. The end: the board commit, the whole-branch review and gate

When every subtask is merged:

1. **Take `main` once** (`SKILL.md`, "Lifecycle", step 3): `git fetch origin`, and when `origin/main` has moved, `git merge origin/main --no-edit` into the integration branch (its own tool call; conflicts resolved within the scope of the files' owners).
2. **The board commit** (`tm-pr-workflow`, "Board", rule 5), the last commit of the branch: the epic's record deleted and its slug removed from every `After:` line and mention (the `chore(board): remove <slug>` form), the records for the follow-ups and drift in `keep-notes.md` that need an owner decision or design (`tm-pr-workflow`, "Board", rule 1: an agent-doable follow-up is a queue entry after the epic, not a record), and the plan's `Status` bullet set to `done`.
3. **Draft the epic PR's description** at `~/agent-workspace/epics/<slug>/keep-pr-body.md`: first line `Title: feat(<scope>): <the epic's one-line summary>` (a valid `type(scope): summary`; it appears in the merge commit), What changed per subtask (the merge commits), Skills/docs followed (the union), Tier 1, Tier 2 (the plan's epic-level Tier 2, with the human checks and their steps), Assumptions, Follow-ups and Drift (each ending `(queue: <slug>)` or `(board: <slug>)`), a "For the owner" part with the notes of the local reviews that escalated, `Reviewer findings`, and the `Board:` line.
4. **One local review and one gate of the whole branch** (the gate's result is the `GATE_EXIT <n> HEAD <sha>` line the gate prints last, read with `scripts/gate-result.sh`, never the exit code of a wrapper or a background task), which are what the push hook reads: `scripts/local-review-prepare.sh <draft>` on the final HEAD (its base, the merge-base with `origin/main`, is exactly right here: the whole epic against `main`), the `pr-reviewer`, `scripts/local-review-record-verdict.sh` (the verdict must be for the HEAD that will be pushed, with no `[blocking]` and a disposition for every `[important]`), then `scripts/pre-push-check.sh` on that same HEAD, full (the epic touches the shared layer and both apps, so the Android and iOS steps and both UI suites run). No commit after the gate: a new commit needs a new review and a new gate. Budgets as `tm-agent-loop`, section 4 and `tm-pr-workflow`, "Retry budget".
5. **Push once, open the PR.** `git push -u origin feature/epic/<slug>` (the hook passes only with the recorded review and the gate marker of that HEAD), then `gh pr create --base main --head feature/epic/<slug> --title "<title>" --body-file <body>` with the body from the draft (`scripts/set-pr-body.sh --print-body <draft>`). `ci.yml` has no push trigger for an epic branch, so the PR's runs are the only runs: one set of the required checks on the PR head, and one more after each fix pushed to it. The PR is not a draft.
6. **Watch CI** (`tm-agent-loop`, section 6, `watching-ci.md`): `scripts/wait-for-checks.sh --review-first <PR>`, then the rest; log `ci-start` and `ci-end`. A red job or a CI reviewer finding: the fix is a commit on the same branch, through the local review and the gate, pushed to the open PR; the limits are the usual (one re-run of a failed job, 2 CI-fix rounds, `tm-agent-loop`, sections 6 and 7). Each round is logged (`ci-fix`).
7. **`main` moves while the PR is open** (strict protection on `main` then blocks the merge). **GitHub's "update branch" is never used** for the epic PR: it makes a merge commit that no local review and no local gate saw. The orchestrator brings `main` in locally: `git fetch origin`, then `git merge origin/main --no-edit` into the integration branch (its own tool call; conflicts resolved within the scope of the files' owners), the local review of the new HEAD (base the merge-base with `origin/main`: the whole epic) and the full gate on it, then the push to the open PR, and CI runs again (`ci-fix` is not the name of this round: log `main-merge`). This is the same way `main` came in before the first push (step 4.1), so one rule covers both. It is not a retry-budget attempt. The owner who sees the PR behind `main` says the command again; he never presses the button.
8. **The Merge check comment** on the epic PR (`tm-agent-loop`, "Auto-merge"): its condition 6 is "no" when the plan or another protected file is in it, so the human merges. The orchestrator never merges the epic PR.

## 5. The report

Before the report is sent and before the PR is opened, `scripts/epic/check-report.sh <the PR description draft>` and then `scripts/epic/check-report.sh <the report text, written to a file>` must pass: each fails and names the file when a protected-path file that the run changed (the plan, a skill, a script, CODEOWNERS, ...) is not in the text, including one that only the last fix of the run touched. The report lists every such file (`PROTECTED_CHANGED <n>` and its lines). Run it again after the last commit: it reads the branch as it is.

The report of `tm-agent-loop`, "Report", ends the run: the epic PR's link and head SHA, the state of CI, the exact merge command (`gh pr merge <n> --merge --match-head-commit <40-character SHA>`), the human checks of the plan's epic-level Tier 2 that the owner has to do with their steps, the notes of the escalated local reviews, and **"Drift found"** with the **"Evidence"** below.

### Evidence (the part that tests the decision to merge locally)

The "Drift found" part has a short measured comparison from the run record, with real numbers and no estimate:

- for each subtask: the wall time of its local review and of its local gate, and the number of fix attempts of each;
- the wall time of the whole-branch review and gate, of the one CI run on the epic PR, and of every re-run or CI-fix round;
- anything that CI or the CI reviewer found that the local gate and the local reviews had not (name it, say which check found it and why the local ones did not), and the reverse (a local finding CI would have missed);
- every flake (the job, the signature, whether a re-run cleared it);
- the number of CI runs on the epic PR's head after the first push (it must be one set of the required checks; two means a duplicate trigger is back), counted with `gh run list --workflow CI --json event,headSha`;
- the assumptions of this skill that the run confirmed or corrected (the worktree `cwd`, the push hook with a merge commit at HEAD, the local merge order, the run record), each with its evidence.

The owner judges the decision from this, not from opinion, and changes it if the evidence says he was wrong.

## Resuming after the PR is open

The same sentence on an epic whose PR is open reads the PR first (`gh pr view <n> --json state,mergeStateStatus,headRefOid`) and does only what is due: CI red or a CI reviewer finding not yet fixed, step 4.6; `main` ahead, step 4.7; everything green and nothing due, the report again (a fresh Merge check comment for the current head). A PR that is merged or closed ends the run: the report says so, and the next run cleans up (`merging-the-epic.md`, "After the merge").

## The queue and the epic

An epic run does not use the local PR queue (`scripts/queue/queue.sh`): the subtasks are not PRs, and the one epic PR is opened at the end of the run, so nothing of the epic is an entry. The heavy-run lock is shared by everything: every gate and every worker's test run goes through `scripts/heavy-run.sh`, and a wait for it is neither a failure nor a gate attempt. While the epic runs, no other work starts in the session: a follow-up found goes to `keep-notes.md` and, at the end, to the board commit or, for an agent-doable one, to a queue entry after the epic is merged. After the epic PR is open the run ends with the report; the queue starts again in the next run. A run of the queue that finds an open epic branch does not touch it.

## What the owner does

- **Before the run:** delete the ruleset for `feature/epic/*` if there is one (the pre-flight says if it applies; the owner deletes it, the orchestrator never does); merge the plan's PR into `main`; have the machine on, logged in as `peter-christofer-bot`, with the iOS secrets config and `local.properties` in the clone.
- **After a stop:** read the report and say the command again with the decision after it (above); that is all the run needs. If the owner expects a stop (for example a deleted test that the plan names), the decision can be given in the first sentence.
- **After the run:** do the human checks of the plan's epic-level Tier 2 on the epic PR's head, review the PR, and merge it with a merge commit (`merging-the-epic.md`). Answer a stop that belongs to the plan; that is the only thing the run asks during its course.
