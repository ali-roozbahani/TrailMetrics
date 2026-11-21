# Commits, push and PR, the PR description

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the sections "Commits", "Push and PR" and "PR description". The rules are unchanged; they are still cited as `tm-pr-workflow`, "Commits", "Push and PR" and "PR description".

## Commits

- Format: `type(scope): summary`, imperative, lowercase after the colon, no trailing
  period. Explain the *why* in the body when it isn't obvious.
- Types in use: `feat`, `fix`, `refactor`, `build`, `docs`, `test` (the set the retired docs listed),
  plus `chore`, which is the most common type in recent history. Use `chore` for work that fits the `chore/` branch prefix but isn't a
  better fit for `docs`, `build` or `test`.
- Scopes in use: a module or platform (`android`, `ios`, `domain`, `data`, `shared`,
  `core`, `route`) or an area (`ci`, `hooks`, `skills`, `learnings`). Omit the scope
  only when the change really spans everything.
- One type per message. Don't combine them (`docs+chore:` in #7 is not the pattern).
- End every commit message with the attribution trailer the session specifies. The one exception
  is a local `git merge origin/main` commit (`tm-agent-loop`, section 9): the squash merge drops it
  from `main`, so it needs no trailer (`git merge origin/main --no-edit`).
- **A bugfix's red evidence goes in a commit message**: the commit that adds the reproducing test, or
  the fix commit when they are one, states the test's name and its failure message on the unfixed
  code. The local and CI reviewers enforce exactly that (`tm-pr-review`, item 4; a missing test or
  missing evidence is blocking), and `tm-testing`, "Bugfixes: red test first", says the same. The PR
  description may repeat it, but the commit message is what the reviewer checks.

## Push and PR

- Before the push: draft the PR description, run the reviewer on the final commit, fix, review again, then write the
  dispositions (`scripts/local-review-gate.sh disposition <sha> '<disposition>' ...`, one
  argument per `[important]` finding in report order). The hook allows the push and
  `gh pr create` only for a report of exactly that commit with no `[blocking]` finding (verdict
  `APPROVE`, or `ESCALATE_TO_HUMAN`) and a disposition for every `[important]` one;
  `scripts/local-review-gate.sh check <sha>` says why not. Report the hook's reason when it
  blocks, never work around it (no `git -c`, no alias, no editing the settings).
- Push the branch you created (`git push -u origin <branch>`), then open the PR against
  `main` with `gh pr create --base main --title "<PR title>" --body-file <file>`. `gh` must be logged in as an account with write
  access to `ali-roozbahani/TrailMetrics`; check `gh auth status` if `gh` fails.
- Never push to `main`, and never enable GitHub's auto-merge setting. An agent merges only
  under the conditions in `tm-agent-loop`; the human merges everything else, after CI is
  green and Tier 2 has passed (every human check the PR lists is done). A human check
  listed under Tier 2 does not block a merge the agent makes: it stays in the PR's
  description, and the human does it when testing the feature (the epic-level Tier 2),
  not before the merge.
- The agent's part does not end at the open PR: the run continues with `tm-agent-loop`,
  sections 6 to 8 (watch CI, read the verdict, merge conditions), and the "Merge check" comment is
  posted on every PR.
- **The PR title becomes the commit on `main`.** PRs are squash-merged as
  `<PR title> (#N)`, so the title must itself be a valid `type(scope): summary`.

### PR description

Required. It is final before the push that starts CI: CI's reviewer reads the description when the run
starts, so a later edit is not what that run reviewed. Write the gate result and the local review's
dispositions into it before the push, and give the PR that body at creation; only what the CI reviewer
itself reports can come after.
Draft it at `~/agent-workspace/pr-body-<slug>.md` before the local review, without
`Reviewer findings`: it is the local reviewer's `TASK` (`scripts/review-task.sh <draft>`), as it
is CI's. The PR is created from it with `--title "<PR title>"` and `--body-file`: an optional `Title:`
first line and the blank line below it are not part of the body, so when the draft has one, write the
body file first with `scripts/set-pr-body.sh --print-body <draft> > <body file>` and give `gh` that
file (a draft without a `Title:` line is the body file itself). A `Board: -slug` line brings that record's Problem and Done when to the
reviewer; a task with no record states its Task and Scope in "What changed". `Reviewer findings` is
added after the reviews. Use these headings, and keep all four even when one is
"nothing to check":

1. **What changed**: the diff in reviewer terms, including what was deliberately *not*
   changed if the Scope named it.
2. **Skills/docs followed**: e.g. `tm-kmp-shared`, `tm-robustness`, `tm-testing`, `tm-pr-workflow`.
3. **Tier 1**: the gate result on the pushed HEAD, which steps ran, and why the iOS steps
   were skipped if they were. For test changes, include test counts before and after
   (from `allTests` JUnit XML, not `./gradlew test`), counted as `test-counts.md` says:
   - Report before and after for each module the PR touches. No repo-wide total.
4. **Tier 2**: for each user-visible behavior the change alters, the automated test that
   covers it (by name), or a human check with its reason and steps (see "Tier 2: what
   automated tests cannot show", `SKILL.md`); or, for a docs-, test-, CI- or skill-only change, an
   explicit "nothing user-visible changes" and why. "Nothing to check on a device" without
   test names is not enough for a change that alters user-visible behavior.

Add these when they apply (the full text of each, with the rule that each Follow-ups or Drift bullet ends with where the item went, is in `pr-description-extras.md`): **Reviewer findings** (one line per `[important]` finding with its disposition), **Assumptions**, **Follow-ups (out of scope, not changed)**, **Drift found (not fixed)**, **Board** (always, one line: `Board: +slug-a, -slug-c` or `Board: no changes`) and **Corrections**.

End the description with the attribution line the session specifies.

**Re-triggering the CI reviewer: one rule.** The reviewer reads the description from the event of its run, so the PR is created with the final
text (`scripts/check-pr-description.sh --final <draft>` passes: the four headings, the `Board:` line, an ending on every Follow-ups and Drift
bullet, no placeholder, the attribution line). If the description must change after the push, edit it with `scripts/set-pr-body.sh`:
once `pr-review.yml` has the `edited` trigger, that edit re-runs the reviewer on the current head by itself, with the new text, and the
agent reads the head's checks again. Until it has, the reviewer's verdict for that head stands on the text it read, and the correction is for
the human; a correction the reviewer must see waits for the next push. Closing and reopening a PR, and re-running the reviewer's run (a
re-run replays the old event text), are never used for this, and need no owner's word because they are not done.

The description of an open PR (the `Reviewer findings` added after the reviews, any later change) is set from the draft with `scripts/set-pr-body.sh <PR number> <draft>`: `gh pr edit` needs the `read:org` scope, which the machine token lacks.
