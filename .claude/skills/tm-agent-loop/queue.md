# The PR queue in the agent loop

Detail of `SKILL.md`, section 9. The queue's own rules (statuses, order, the limit of 5, what each
`next` line means) are in the header of `scripts/queue/queue.sh`; the scripts named here say in
their headers what they read and print. This file says how the loop uses them.

## What goes in

- **The task's own PR** is the queue's first entry: once its branch is committed and its PR
  description drafted, `scripts/queue/queue.sh add <slug> --branch <branch> --kind agent|owner`
  and `set <slug> status=ready`; it is then pushed when `next` says `PUSH`, like any entry. Add
  the follow-ups one at a time as they are found, and read the `next:` line that `add` and `set`
  print: after the first entry is `ready` it is `PUSH`, so the first PR is pushed before any
  follow-up is built (in the C3 dry run all four entries were built first and the first PR waited
  36 minutes).
- **Every follow-up and drift the agent can do** (`tm-pr-workflow`, "Board", rule 1) is an entry
  of its own: `add <slug> --branch <type>/<slug> [--after <parent slug>] [--kind owner]`.
  `--after` only when it needs the parent's change; `--kind owner` when its PR will touch a
  protected path or needs the owner's review. The slug is its name in the parent's PR description
  (`(queue: <slug>)`) until its PR exists.
- **An `[important]` reviewer finding the agent will fix in a PR of its own** is such an entry: `add`
  it first, then dispose the finding as `queued <slug>` (`tm-pr-review`, "Orchestrator's part",
  step 5). The push gate accepts the disposition only for a slug that is an entry of the queue
  file and not dropped; it does not check that the entry fixes the finding.
- **Not in the queue:** an item that needs an owner decision or design, an epic, a change under
  `.github/workflows/` (only the owner can push it), and an item `add` refuses because 5 entries are
  open. Those get a `BOARD.md` record instead.
- `kind` is decided when the entry is added. A pushed agent entry whose Merge check has a "no"
  (an `ESCALATE_TO_HUMAN`, a protected path found late) is handed to the owner like an owner entry;
  nothing else is pushed until the owner merges or closes it.

## The cycle

Repeat until `next` prints `DONE`, or the owner wait below runs out, or a stop condition of
`SKILL.md` holds. Each time: `scripts/queue/queue.sh next`, then do what it says.

Every `add` and `set` ends with `next: <line>`, the answer `next` would give after that change.
Act on it: the scripts decide the order, not the plan you made earlier.

- `BUILD <slug>`: `set <slug> status=building` first. Create its branch from the local `main`, or,
  for an entry with a parent, from the parent's local branch. Do the work as sections 2 and 3 say
  (code skills, sweep, board, protected paths), commit, draft its PR description with a line
  `Follow-up of #<parent PR>` under "What changed", then
  `set <slug> status=ready`. No local review and no gate yet: they run once, at `PUSH`.
- `FINISH_BUILD <slug>`: the entry was left `building` (an earlier session, an interruption). Check
  out its branch, read what is committed, finish it as for `BUILD`.
- `PUSH <slug>`: check out its branch, `git fetch origin`, and when the branch is behind
  `origin/main` (always for an entry with a parent, which is pushed only after the parent's merge),
  `git merge origin/main --no-edit` in its own tool call (a merge commit, which needs no attribution
  trailer because the squash merge drops it; never a rebase). Resolve a conflict
  by keeping both changes' intent. Then the local review (section 4), the gate (section 5), the
  push and `gh pr create --base main`, then `set <slug> status=pushed pr=<N>`. When the PR opens,
  put `(#<N>)` in place of `(queue: <slug>)` in the parent's description (`scripts/set-pr-body.sh
  <parent PR> <parent draft>`, also when the parent is merged). Then watch it (section 6).
- `WAIT <slug> #<N> <kind>`: nothing is left to build. While the PR's own checks run, the wait is
  section 6 (`scripts/wait-for-checks.sh`). Otherwise, and for every PR handed to the owner, run
  `scripts/queue/watch-prs.sh --wait` as a background command (`run_in_background`, timeout above
  180 minutes) and act on the events it prints.
- `HOLD <slug> after <parent>`: the parent was dropped. When the entry still makes sense on its
  own, add it again under a new slug without `--after` and drop the old one; otherwise drop it.
  Either way, name it in the report.
- `DONE`: the queue is empty; the run ends with the report.

While a background wait runs you do not end your turn; you may take `BUILD` and `FINISH_BUILD`
actions meanwhile, never `PUSH` or a merge.

## Recording events

Every change of an entry's state goes into the queue file with `queue.sh set` at once, before the
next action. The file is the only state a later session gets (besides GitHub).

| Event                                            | Record                                  |
| ------------------------------------------------ | --------------------------------------- |
| build started / finished                         | `status=building` / `status=ready`      |
| PR opened                                        | `status=pushed pr=<N>`                  |
| merged (by the agent, or `MERGED` from the watch)| `status=merged`                         |
| `CLOSED` (closed unmerged), or abandoned         | `status=dropped`                        |

Events of `watch-prs.sh --wait` that do not change the status are acted on:

- `CHECKS_DONE green|red`: sections 6 to 8 for that PR (verdict, failed jobs, merge conditions).
- `BEHIND #<N>`: `main` moved outside the queue (the owner merged something). Run
  `scripts/queue/update-branch.sh <N>`: `UPDATED` → watch the new head (section 6, from
  `--review-first`); `CONFLICT` → `git merge origin/main` locally, review and gate again, push;
  `NOT_MERGE_ONLY` → local review of the new head before merge condition 5 can hold; `RACE` → read
  the PR again; `REFUSED` → report it.
- `HEAD_MOVED #<N>`: someone else changed the branch. `scripts/queue/local-verdict-for-head.sh <N>`
  says whether the local review still holds (merge-only updates only); `NONE` → stop for that PR
  and report.
- `TIMEOUT`: the owner wait ran out (below). `NONE_OPEN`: nothing to watch; run `next` again.

## Merge, hand-over and the read of main

- **Merge.** After the PR's checks are done (section 6), check the six conditions of section 8 for
  its head SHA; `scripts/queue/watch-prs.sh --once` must show `behind=0` for it (otherwise
  `BEHIND` above). All "yes" and the read of `main` below clean: merge with the command of
  section 8, post the Merge check comment, `set <slug> status=merged`.
- **Condition 5 for an updated head.** When the head is a merge-only update of a reviewed commit
  (GitHub's update through `update-branch.sh`, the only update that is not pushed locally), the
  recorded verdict is that of the reviewed commit: `scripts/queue/local-verdict-for-head.sh <N>`
  must print `APPROVE <reviewed sha> (<n> updates)`, and the dispositions of that commit's report
  count. A head pushed from the clone always has its own review (the push hook requires it).
- **Hand-over.** Any condition "no": post the Merge check comment for the head SHA (a fresh one
  after every new head), leave the entry `pushed`, and go on with `next`.
- **Owner PRs stay current.** Owner entries are pushed last, when everything ahead is merged, and
  one PR of the queue is pushed at a time, so the agent's own merges never leave an owner PR behind
  `main`. Only a merge outside the queue can (`BEHIND` above); after the update, post a fresh Merge
  check comment.
- **The read of `main` right before each merge.** The queue does not wait for the push run of a
  merge commit, the agent's or the owner's: `main` requires branches to be up to date, so the tree
  that lands is the tree CI tested, a red run there is a flake or infrastructure, and the next PR's
  own CI covers the same code. Before every merge (and before the start of a task, as
  `tm-pr-workflow`, "Before starting" says) take one instant, non-blocking read:

  ```bash
  scripts/main-ci-status.sh --recent 5
  ```

  `unacknowledged-red=0`: merge. A run still `running` is not a reason to wait. An unacknowledged
  red run, or a read that fails (exit 4): stop everything (no push, no merge, no build) and report
  it as `tm-pr-workflow`, "Before starting" says; only the owner's "go on" acknowledges it.

## The owner wait

When only PRs handed to the owner are left (the next action is `WAIT` on one, and its Merge check
is posted), the run waits for them with `watch-prs.sh --wait` (default 180 minutes; that is the
run's maximum wait). A `MERGED` goes on with `next`. On `TIMEOUT` the run ends with
the report, which lists, in queue order, each PR waiting for the owner with its exact merge command
and the full 40-character head SHA:

```bash
gh pr merge <N> --squash --match-head-commit <40-character SHA> --subject "<PR title> (#<N>)" --body ""
```

followed by the entries not pushed yet and what each waits for, and the one line with the recent
status of `main` that `SKILL.md`, "Report" asks for.

## A new session

A session never continues from memory. It starts with `tm-pr-workflow`, "Before starting", then
`scripts/queue/queue.sh show`, `scripts/queue/watch-prs.sh --once` and `queue.sh next`. Where the
file and GitHub disagree, GitHub wins: a PR merged or closed meanwhile is recorded (`set`) first.
A `building` entry is finished (`FINISH_BUILD`). A run that finds open entries continues them
before it starts a new task; the new task's PR then enters the same queue.

## The report

The shape of `SKILL.md`, "Report" (Done, Not done, Not verified), with one line per queue entry of
the run under Done or Not done: slug, PR, and what it ended as: `merged <merge sha>`, `handed to
the owner` (with its merge command), `dropped` (why), or `not pushed` (its status and what it
waits for).
