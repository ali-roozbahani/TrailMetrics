---
name: tm-agent-loop
description: Use for every TrailMetrics run that ends in a PR, a named task or a board pick ("take the next task", "work the board"). Covers one run from picking the record with scripts/check-board.sh --next (only a run without a named task) to its merged PR and the PRs of its follow-ups, worked through the local PR queue (scripts/queue/), with the PRs that need the human handed over and reported — implement, protected-path check, local review and its fix budget, gate, push, PR, watching CI (a failed job, its one re-run), reading the CI reviewer's verdict from its annotation, the merge conditions, auto-merge, after-merge cleanup, the queue cycle (queue.sh next, watch-prs.sh, the read of main's recent runs before each merge, the owner wait), and when to stop and report. Not for the per-PR rules themselves (see tm-pr-workflow) or for epics (see epic-orchestration).
---

# TrailMetrics agent loop

One run takes one task, named or a board record, to a PR, and every follow-up it finds that the
agent can do to a PR of its own, through the local PR queue (section 9, `queue.md`). The rules for
each step live in other skills; this skill gives the order, the decisions between steps and the
merge conditions. The merge conditions and the reading of the CI verdict are the plan's Decisions 5 to 8
(`docs/epics/agentic-dev-loop.md`); among the skills they are written down only here.

## Topic files

Read each file when the run reaches its topic, not before. Section numbers and headings are unchanged, so a
reference to `tm-agent-loop`, section N, is found in this file or in the file named here.

| File | Read it when |
|---|---|
| `watching-ci.md` (section 6) | right after the first push of a PR branch, and after every later push: waiting for the checks, the reviewer first, a failed job, its one re-run, the timeouts |
| `merge.md` (sections 7 and 8, "Auto-merge", "After-merge cleanup") | when the CI reviewer's verdict is posted, and before every merge: reading the verdict, the six merge conditions, the Merge check comment, the cleanup |
| `ci-report.md` | when a CI report has to be downloaded, or the merge conditions are read with their commands |
| `queue.md` (section 9 in detail, "The full UI run on main") | whenever a queue entry is added, built, pushed or reported, and at the queue's `DONE` |
| `subagents.md` | before any subagent is started |
| `denied-commands.md` | when the permission classifier denies a command |


## Preconditions

Do the start-of-run steps of `tm-pr-workflow`, "Before starting" (login, clean tree, `main`
pulled, merged branches deleted, `fetch --prune`).

Then, before any new work, run `scripts/dev/clean-agent-workspace.sh` and say in the report how many
files it removed. It also runs by itself whenever `queue.sh set` records an entry as merged or dropped, so a
long queue session cleans as it goes; it deletes loose files of any name once they are over 3 days old, never
state and never what an open entry uses (`clean-agent-workspace.sh`, header). A file you want kept for good
starts with `keep-`.

A run whose gate will run the iOS steps needs the git-ignored iOS secrets config (README
"iOS", step 2) in the clone. The gate checks that it exists and stops at once if it is
missing; the agent never reads or creates it, and stops and reports instead.

## One task per run

A named task skips only section 1: after "Before starting" and the work it goes through
sections 3 to 9, Auto-merge, After-merge cleanup, Stop and Report exactly as a picked one.

The task is done when its PR and every PR queued from it are merged or handed to the owner. A run
ends at the queue's `DONE`, when the owner wait runs out, or at a stop condition (section 9). A
session continues from `scripts/queue/queue.sh show` and GitHub, never from memory. The next
task is a new run; the human clears the session between runs.

## 1. Pick (only a run without a named task)

```bash
scripts/check-board.sh --next
```

- `figma-design-system`, or an epic with no plan on `main` approved by the owner: don't code. Write the plan for
  the human to approve (`tm-pr-workflow`, "Board", rule 0) and stop.
- An epic whose approved plan is on `main`: run it only on the owner's command "run the epic `<slug>`", by
  `epic-orchestration` (`running-an-epic.md`), which is a run of its own and does not use the queue. Without that
  command, report that the epic waits for it and do not start it.
- A record that is unclear, or whose Done when contradicts the code: stop and report.
- Otherwise the record is the task. Its Problem and Done when are what the PR description
  must cover; the reviewer's `TASK` is that description (section 4), and the `Board: -slug`
  line brings the record to it.

## 2. Implement

Follow `tm-pr-workflow` from "Before starting" on: branch prefix and name, commits with
`git commit -F <file>`, Boundaries, "Docs follow the code you changed", the "Board" rules,
and the record deleted in its own commit. Load the code skills for the paths you touch.
Scope is the task (a picked record's Done when) and the same-subject fixes of that sweep, nothing
else.

## Subagents (tools of sections 2 and 4)

The main agent is the orchestrator: it, and only it, integrates (takes the commits in, runs the review and
the gate, pushes, opens the PR, watches CI, merges, works the queue). A subagent never does, and its work is
a claim: the diff and the gate decide. `subagents.md` has the rest, and is read before any subagent is
started: the `explorer` (an open-ended or large search, never a targeted lookup), the decision between
implementing yourself, one `implementer` and a split of at most 2, the procedure with
`scripts/subagent/worktree.sh` and the task file, heavy runs one at a time through
`scripts/heavy-run.sh`, and why nothing below the orchestrator spawns.

## 3. Protected paths

```bash
scripts/check-protected-paths.sh --base "$(git merge-base HEAD origin/main)"
```

A task may touch protected paths if its record says so or for a same-subject sweep fix; the
PR is then the human's to merge (say so in the report). Never touch a protected path as an
unrelated side effect.

## 4. Local review

Draft the PR description first (`tm-pr-workflow`, "PR description", `commits-push-pr.md`; no `Reviewer findings`
yet), then run the `pr-reviewer` on the final HEAD as `tm-pr-review`, "Orchestrator's part"
describes: `scripts/local-review-prepare.sh <draft>` fills the inputs and writes its message to a
file, the reviewer is started with the two-line prompt it prints, and
`scripts/local-review-record-verdict.sh` records the verdict. A hook (`scripts/claude-hooks/require-local-review.sh`) captures the
reviewer's own report when it finishes and refuses `git push` and `gh pr create` unless the report
of the commit that would be pushed has no `[blocking]` finding and a disposition for every
`[important]` one: write them with `scripts/local-review-gate.sh disposition <sha> '<disposition>' ...`
(one per finding, `fixed in <sha>` | `board record <slug>` | `queued <slug>` | `rejected: <reason>`,
section 7's reason rule) before the push. A new commit needs a new review. A blocked push is reported with the hook's reason.

- `APPROVE`: continue.
- `CHANGES`, or blocking findings under `ESCALATE_TO_HUMAN`: fix them as a new commit and
  review again. That is one review fix attempt. The budget is **2 review fix attempts per
  PR**, separate from the gate's 2 fix attempts (`tm-pr-workflow`, "Retry budget", `retry-budget.md`). If the
  third review still has a blocking finding: stop, don't push, report the findings.
- Notes and `[important]` findings never trigger another round; each `[important]` gets its
  disposition in the PR description (`tm-pr-review`, "Orchestrator's part", step 5).
- `ESCALATE_TO_HUMAN` with no blocking findings: continue; the human decides.
- `NO_VERDICT` is never recorded: fix the cause and ask again. Environment problems are not
  attempts.

## 5. Gate, push, PR

Run `scripts/pre-push-check.sh` until green within the retry budget (its result is its own last line, `GATE_EXIT <n> HEAD <sha>`), write the
gate result into the description and run `scripts/check-pr-description.sh --final <draft>`: CI's reviewer reads the description when its
run starts, so the PR is created with its final text. Then push and open the
PR with `gh pr create --base main --title "<PR title>" --body-file <file>` (`tm-pr-workflow`,
"Tier 1", "Push and PR", "PR description"). A new commit needs a fresh review and a fresh gate run.

A diff that touches `.github/workflows/` is pushed like any other, as a PR (owner decision of
2026-11-15; it replaces Decision 1 of the agentic-dev-loop plan; the removal of CI's UI jobs is one such
change). The owner still merges it (a protected path), and still changes the branch protection and
`.claude/settings.json` alone. Two cases the owner pushes, not the agent: a diff that touches
`.github/workflows/pr-review.yml` (the file that holds the reviewer's API key step, which a `pull_request`
run takes as it is on the PR head), and a diff that adds a reference to `secrets` in any workflow file.
`scripts/check-workflow-guard.sh` is a gate step that fails on exactly these two, so the push hook, which
allows a push only after a passing gate, keeps them from being pushed. When it fails, do not push and do
not split the change to get around it: write the change as a patch file (`git format-patch` of the commit,
or a `git diff` of the file) in `~/agent-workspace/`, and hand it to the owner with one line saying what it
does and which file it touches. No GitHub Environments with required reviewers are used for this (a click
for every push of every PR). A push
authenticates through the `gh` credential helper only: the push hook blocks any `git push` unless the
checkout's effective `credential.helper` list is exactly `!gh auth git-credential`, so no keychain login
can answer first. When GitHub refuses the push (the machine token has no `workflow` scope: "refusing to
allow an OAuth App to create or update workflow"), or a hook stops it, stop after the gate: report the
exact refusal and the exact change the owner has to make (the token's scope, the hook). Never work
around it: no other login, no `git -c`, no API call that writes the file.

## 9. The queue

How, with the commands: `queue.md`; the queue's rules: the header of `scripts/queue/queue.sh`.

- The task's PR is the first entry; every follow-up and drift the agent can do is an entry and a
  PR of its own (`tm-pr-workflow`, "Board", rule 1). Board instead: owner decision or design, an
  epic, an entry over the limit of 5.
- Do what `scripts/queue/queue.sh next` prints (`add` and `set` end with a `next:` line that is the
  same answer: follow it, not your own plan, so a second entry is built only while the first is
  pushed), and record every change of an entry's state with
  `queue.sh set` before the next action. At `PUSH`: merge `origin/main` when behind, then review
  and gate once. Never rebase, force-push or open a PR against a base other than `main`.
- Wait in the background (section 6 for the pushed PR's checks, `scripts/queue/watch-prs.sh --wait`
  otherwise); never end the turn while a wait runs.
- Merge when the six conditions hold and the read of `main` right before it shows
  `unacknowledged-red=0` (one instant `scripts/main-ci-status.sh --recent 5`; a run still in
  progress is not a reason to wait; an unacknowledged red run stops everything, as at the start of
  a task), else hand over with a fresh Merge check comment. A PR behind
  `main` from a merge outside the queue: `scripts/queue/update-branch.sh` (the fallback).
- Only owner PRs left: wait at most 180 minutes, then report them in queue order with their exact
  merge commands (full 40-character SHA).

## Stop and report

- The identity is wrong, or an environment failure.
- The gate's retry budget or the review fix budget is exhausted.
- The record is an epic with no approved plan or no owner command, or is unclear.
- A protected-path change the task did not call for.
- CI still red on the same SHA after its one re-run, the script refuses, a third failing push after
  2 CI-fix rounds, or the reviewer check is `UNKNOWN` (section 6).
- The reviewer's report cannot be downloaded after `CHANGES` (section 7).
- Anything that would need a force-push, an amend, a cancelled run (other than the old head's runs, through
  `scripts/cancel-head-ci.sh`, once a fix is decided) or reading a credential.
  A run cancelled because a newer push superseded its SHA is not that case: the checks of the
  CURRENT head SHA count, and an older SHA's cancelled run is expected. Closing and reopening a
  PR is never a way to re-trigger the reviewer (`tm-pr-workflow`, `commits-push-pr.md`, "PR description": the rule is stated
  there once); after any description edit read the current head SHA's checks again.
- The read of `main` right before a merge shows an unacknowledged red run (section 9), or fails.
- A merge condition that is "no" is not a stop: the PR is handed over and the queue goes on.

## Report

The final report to the human has three parts: Done, Not done, Not verified.

- Done: each item with the command run and what it printed (exit code, SHA, URL, counts),
  never a conclusion alone. Who pushed, and which SHA, branch or credential, comes from
  `git` or `gh` output of this run, not from memory.
- A check that did not run, or whose output was not read, is under Not verified, never
  shown as passed. A blocked or denied command is quoted (the message) and reported, not
  worked around.
- The PR description keeps its own headings (`tm-pr-workflow`); this shape is for the chat report.
- It says what each queue entry ended as, PRs waiting for the owner in queue order with their merge
  commands (`queue.md`, "The report").
- One line per subagent run (agent, name, its `STATUS`, and what you checked after it: the `take`
  output and the diff you read), and the choice between yourself, one implementer and a split with its
  reason.
- One line with the recent status of `main`, read once at the end (`scripts/main-ci-status.sh
  --recent 5`: its summary line and any red or running run), under Done, or under Not verified when
  the read failed.
- One line with the full UI run on `main` (section 9: the output of `scripts/main-ui-run.sh --auto`, `NOT_DUE`
  with its reason or the result of the run), under Done, or under Not verified when it could not run.
- The final report is sent only when the queue ends (`DONE` or the owner wait ran out) or after a
  stop-and-report condition, never between opening a PR and its Merge check; an interim line saying "continuing" is not
  a report and must be followed by the next tool call in the same turn.

## Never

- Push to `main`, force-push or amend, or cancel a CI run (the one exception: `scripts/cancel-head-ci.sh`, for
  the head that a decided reviewer-finding fix is about to replace).
- Enable GitHub's auto-merge setting (it stays off) or use `gh pr merge --auto`; change
  repository settings; edit a protected path outside the task.
- Read other credentials. The deny rules in `.claude/settings.json` are best effort, not a
  wall: don't try to get around them.
- Merge a PR for which one of section 8's conditions is not met, or an epic PR into `main`.
- Let a subagent push, open, review or merge a PR, run the gate, touch the queue or the review
  records, or integrate: only the orchestrator does (section "Subagents"; the subtask worker of an epic is an
  `implementer` too, `epic-orchestration`, "Roles"). Start a heavy run around `scripts/heavy-run.sh`.
- Do not join git commands that depend on each other with `;`. Join them with `&&`, so a failed
  command stops what follows (a failed `git revert` once let a following
  `git commit --amend` run). Run a history-changing command (`git revert`, `merge`,
  `cherry-pick`, `stash`) in its own tool call and read its output before the next command.
  The read-only review input block of `tm-pr-review`, "Orchestrator's part", is not affected.
