# PR description: the headings added when they apply

Moved word for word from `SKILL.md`, then `commits-push-pr.md`, "PR description" (from "Add these when they apply" to "Corrections"). The rules are unchanged; `commits-push-pr.md` keeps the list of headings.

Add these when they apply. Recent PRs use them consistently:

- **Reviewer findings**: present when a reviewer report (local or CI) has an `[important]` finding
  or a `[blocking]` one that was fixed. One line per `[important]` finding, with its disposition:
  `fixed in <sha>` | `board record <slug>` | `queued <slug>` | `rejected: <reason a human can
  check>` (`tm-pr-review`, "Orchestrator's part", step 5); a fixed `[blocking]` finding is listed with its fix commit.
- **Assumptions**: every place the docs were ambiguous and the call you made (see
  Boundaries).
- **Follow-ups (out of scope, not changed)**: problems found but deliberately left out of this
  PR because they are of another subject, over the sweep's bound, need a human decision, or
  break a boundary. Say what the fix would be and why it is left.
- **Drift found (not fixed)**: docs that disagree with code this task didn't change (see
  "Docs follow the code you changed" under Boundaries).
- In both, each bullet ends with where the item went ("Board", rule 1): `(#<n>)` for its PR,
  `(queue: <slug>)` while its queued PR does not exist yet (replaced by the number once it
  opens, also on a merged PR), or `(board: <slug>)` for its `BOARD.md` record. A bullet with
  none of them breaks rule 1.
- **Board**: always, as one line: `Board: +slug-a, +slug-b, -slug-c`, or `Board: no changes`.
- **Corrections**: if an earlier PR stated something wrong, correct it explicitly (see
  #34's "Correction to #33").
