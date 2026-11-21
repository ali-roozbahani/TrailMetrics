# The PR queue in the agent loop

Detail of `SKILL.md`, section 9. The queue's own rules (statuses, order, the limit of 5, what each
`next` line means) are in the header of `scripts/queue/queue.sh`; the scripts named here say in
their headers what they read and print. This file says how the loop uses them.

`add` and `set` run under a lock on the queue file (`<queue file>.lock`): two of them at once, from
two sessions, wait for each other instead of losing one update, and one that cannot get the lock in
30 seconds refuses (exit 1; run it again). `show` and `next` need no lock.

Only the orchestrator (the main agent) runs `queue.sh`, the watch and the review scripts: an
`implementer` subagent is refused them by its guard hook (`SKILL.md`, "Subagents").

## What goes in

- **The task's own PR** is the queue's first entry: once its branch is committed and its PR
  description drafted, `scripts/queue/queue.sh add <slug> --branch <branch> --task <file> --kind agent|owner`
  and `set <slug> status=ready`; it is then pushed when `next` says `PUSH`, like any entry. Add
  the follow-ups one at a time as they are found, and read the `next:` line that `add` and `set`
  print: after the first entry is `ready` it is `PUSH`, so the first PR is pushed before any
  follow-up is built (in the C3 dry run all four entries were built first and the first PR waited
  36 minutes).
- **Every entry carries its task text**, so a session that did not queue it can build it: `add` needs
  `--task <file>` (or `--task -` for stdin) and refuses without a text, an empty one included. The text
  is kept in `tasks/<slug>.md` next to the queue file and printed by `queue.sh task <slug>`. Write it as
  the task template asks (what to do, its scope, when it is done).
- **Every follow-up and drift the agent can do** (`tm-pr-workflow`, "Board", rule 1) is an entry
  of its own: `add <slug> --branch <type>/<slug> --task <file> [--after <parent slug>] [--kind owner]`.
  `--after` only when it needs the parent's change; `--kind owner` when its PR will touch a
  protected path or needs the owner's review. The slug is its name in the parent's PR description
  (`(queue: <slug>)`) until its PR exists.
- **An `[important]` reviewer finding the agent will fix in a PR of its own** is such an entry: `add`
  it first, then dispose the finding as `queued <slug>` (`tm-pr-review`, "Orchestrator's part",
  step 5). The push gate accepts the disposition only for a slug that is an entry of the queue
  file and not dropped; it does not check that the entry fixes the finding.
- **Not in the queue:** an item that needs an owner decision or design, an epic,
  and an item `add` refuses because 5 entries are open. Those get a `BOARD.md` record instead. An epic run
  does not use the queue either: its subtasks are not PRs (they merge locally into the integration branch) and its one PR
  is opened at the end of the run, so none is an entry, and an epic starts only when the queue is `DONE` or waits for the owner alone
  (`epic-orchestration`, `running-an-epic.md`, "The queue and the epic"). A
  change under `.github/workflows/` is an entry like any other (the owner merges its PR), except the two
  cases the owner pushes (`SKILL.md`, section 5): a change to `pr-review.yml` and one that adds a reference to `secrets`.
- `kind` is decided when the entry is added. A pushed agent entry whose Merge check has a "no"
  (an `ESCALATE_TO_HUMAN`, a protected path found late) is handed to the owner like an owner entry;
  nothing else is pushed until the owner merges or closes it.

## The cycle

Repeat until `next` prints `DONE`, or the owner wait below runs out, or a stop condition of
`SKILL.md` holds. Each time: `scripts/queue/queue.sh next`, then do what it says.

Every `add` and `set` ends with `next: <line>`, the answer `next` would give after that change.
Act on it: the scripts decide the order, not the plan you made earlier.

- `BUILD <slug>`: read its task with `queue.sh task <slug>`, then `set <slug> status=building`. Create its branch from the local `main`, or,
  for an entry with a parent, from the parent's local branch. Do the work as sections 2 and 3 say
  (code skills, sweep, board, protected paths), commit, draft its PR description with a line
  `Follow-up of #<parent PR>` under "What changed", then
  `set <slug> status=ready`. No local review and no gate yet: they run once, at `PUSH`.
- `FINISH_BUILD <slug>`: the entry was left `building` (an earlier session, an interruption; its task is
  `queue.sh task <slug>`). Check
  out its branch, read what is committed, finish it as for `BUILD`.
- `PUSH <slug>`: check out its branch, `git fetch origin`, and when the branch is behind
  `origin/main` (always for an entry with a parent, which is pushed only after the parent's merge),
  `git merge origin/main --no-edit` in its own tool call (a merge commit, which needs no attribution
  trailer because the squash merge drops it; never a rebase). Resolve a conflict
  by keeping both changes' intent. Then the local review (section 4), the gate (section 5), the
  push and `gh pr create --base main --title "<PR title>" --body-file <file>`, then `set <slug> status=pushed pr=<N>`. When the PR opens,
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

`set <slug> status=dropped` is refused while an open entry comes after `<slug>` (dropping it would hold that
entry; a merged PR is `status=merged`, not dropped). Drop the dependant or re-point it first, or give
`--force` (`queue.sh set <slug> --force status=dropped`) when the owner decided that.

`set ... status=merged` and `status=dropped` also run the workspace cleaner and print its summary line
before the `next:` line, so the workspace is cleaned as the queue goes (`SKILL.md`, "Preconditions"). It
keeps state and every file an open entry uses, so it is safe in the middle of the queue.

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

  `unacknowledged-red=0`: merge. A run still `running` is not a reason to wait, and a cancelled run (`unverified`,
  exit 5) is reported with what verifies it and is not a stop (`tm-pr-workflow`, "Before starting"). An unacknowledged
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

## The full UI run on main

Moved word for word from `SKILL.md`, section 9 (the bullet that was there). The rule is unchanged; it is still cited as `tm-agent-loop`, section 9.

- **The full UI run on main** (owner decision of 2026-11-15). When `queue.sh next` prints `DONE`, before the
  final report, with the clone on a clean, pulled `main`, run `scripts/main-ui-run.sh --auto`. The script
  decides, not you: it keeps the SHA of the last full run of both platforms' UI suites and runs only when `main`
  has code changes since (the classifier's `--ui-scope` is not `none`) or no run is recorded; a docs-only
  history prints `NOT_DUE`. It runs the suites like the gate does (same runners, pins, limits, no retry),
  records the result, and on a red keeps the logs and adds the queue entry `main-ui-red-<sha>`: that entry is
  the first of the queue, and `queue.sh next` says what to do (a `bugfix/` PR through the gate). A run that was
  due when a session ended is shown by `scripts/main-ui-run.sh --status` at the start of the next task
  (`tm-pr-workflow`, "Before starting"): run `--auto` then if the queue is empty. Before a release (a tag, a
  store build) run `scripts/main-ui-run.sh --release`: it runs when due and exits 0 only when the full run of
  the current `main` is green. Nothing in this repository releases yet, so the release step must call it.
