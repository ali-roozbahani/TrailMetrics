# Board

Moved word for word from `SKILL.md`, "Board". The rules are unchanged; they are still cited as `tm-pr-workflow`, "Board", rule N.

`BOARD.md` at the repo root is the backlog of what the agent does not do on its own: epics,
and tasks and drift that need the owner. Follow-ups the agent can do are PRs of the local queue
(`tm-agent-loop`, section 9), not records. A record exists only while its item is open. Its header gives the record format, including `Order` (unique
integer, ascending = do first, across all sections) and the optional `After` (slugs that must
be gone from the board first). `scripts/check-board.sh` enforces the format; it is the first
step of the gate and of CI's `tooling` job.

0. **Picking work.** An agent started without a named task takes the record that
   `scripts/check-board.sh --next` prints. If that record is an epic (or
   `figma-design-system`), it starts with the plan under `docs/epics/` for the human to
   approve, not with code. An epic whose approved plan is on `main` is run only on the owner's
   command "run the epic `<slug>`" (`epic-orchestration`, "The command").
1. **Add.** Everything this PR leaves for later that the sweep ("Docs follow the code you
   changed") does not fix goes somewhere, in every run, whether or not the task came from the
   board. A same-subject item within the bound is fixed, never left. Of the rest:
   - **The agent can do it** (another subject, over the sweep's bound, a protected path the
     owner merges): a queue entry and a PR of its own (`tm-agent-loop`, section 9), never a
     record.
   - **A `BOARD.md` record, in the same PR**, only for: an item that needs an owner decision
     or design; an epic, and the follow-ups its final board PR records (rule 5); an item the
     queue refuses
     because 5 entries are open; a finding of an owner-opened sweep (rule 4); and a flake escalated
     at count 3 ("Flake log"; a runner-not-acquired failure never is). An `[important]` reviewer finding not fixed in the PR is deferred as
     `queued <slug>` (a queue entry and a PR of its own, the push hook checks that the entry exists)
     or, when it is one of the items above, as `board record <slug>`.
     Each record states that one-line reason in its Problem; a record whose only reason is
     that the agent could do it breaks this rule. The human decides when it is done, not
     whether it is recorded.
   Each item is listed under "Follow-ups (out of scope, not changed)" or "Drift found (not
   fixed)" with its PR, queue entry or record ("PR description"). Every new record gets an
   `Order` and, only if it truly can't start before another record is done, an `After`.
2. **Delete.** When the task starts from a board record, delete that record in the PR that
   does the work, as its own commit (`chore(board): remove <slug>`).
   A PR closed unmerged never deletes it from `main`. If the work only partly resolves
   the record, narrow its Problem/Done when instead. If the record is obsolete, delete it
   and say why in the PR. The same commit removes the slug from every other record's
   `After` and from every board mention in the skills and docs, or `check-board.sh` fails. It also
   removes or rewords the slug wherever else it is named (`CI_FLAKES.md`, `LEARNINGS.md`, any file):
   `check-board.sh --base` (the gate passes the merge-base; CI's pull_request run fetches the base)
   fails on every file that still names the slug of a record deleted since the base.
   A mention in a historical plan under `docs/epics/` stays as written: the check only prints
   a notice for it.
3. **Report.** The PR description gets one line: `Board: +slug-a, +slug-b, -slug-c`, or
   `Board: no changes`.
4. **No board-only PRs.** Never open a PR just to update the board. The human or planner
   passes items found outside a PR into the next task's prompt; add them in that PR. The
   only exceptions are an epic's final board PR (rule 5) and a sweep PR: a PR that changes
   only `BOARD.md` is allowed when every record it adds has `Source: sweep <skill>`, the
   `<skill>` of each is on the "Open sweeps" line below, and its description says under
   "What changed" that the owner's sweep task names it. The reviewer checks the Source lines
   and that sentence; nothing else about such a PR is exempt. The owner removes a name from
   the line when its stage is done, and sets the line to `none` when the sweep ends.
   Open sweeps (the owner edits this line, in a protected PR): none.
5. **Epics.** Parallel subtask workers never edit `BOARD.md`, because their edits would
   conflict (this overrides rule 1 for them). They list drift and follow-ups in their PR
   description. Once every subtask is merged into the epic branch, the orchestrator opens
   **one** final board PR into the epic branch. It is not a plan subtask (not in the plan,
   no `allowed_paths`). It adds the records the subtasks reported, deletes the epic's own
   record if the epic started from one, sets the plan's `Status` to `done` (a protected
   path: the human merges this PR), and carries the `Board:` line. It reaches `main`
   with the epic PR, whose own `Board:` line repeats those changes. An epic record points
   to its plan under `docs/epics/`.
6. **Leave other records alone.** Don't delete or rewrite a record you aren't resolving.
   Never rename or renumber a slug. The one exception: a PR may change the `Order` of other
   records only to make room for an insertion, and says so under "What changed".

New slugs are kebab-case, unique in the file and descriptive (never a counter), so two
PRs can't create the same one. A new record goes in the section for its type, at the
position its `Order` gives it (records in a section are sorted by `Order`).
