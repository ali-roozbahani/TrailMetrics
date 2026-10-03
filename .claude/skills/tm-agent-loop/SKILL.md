---
name: tm-agent-loop
description: Use when a TrailMetrics session is started to work through the board without a named task ("take the next task", "work the board"). Covers one run from picking the record with scripts/check-board.sh --next to an open (and, after the trial, merged) PR — implement, protected-path check, local review and its fix budget, gate, push, PR, waiting for CI, reading the CI reviewer's verdict from its annotation, the merge conditions, Trial mode, after-merge cleanup, and when to stop and report. Not for the per-PR rules themselves (see tm-pr-workflow) or for epics (see epic-orchestration).
---

# TrailMetrics agent loop

One run takes one board record to a PR. The rules for each step live in other skills; this
skill gives the order, the decisions between steps and the merge conditions. The merge
conditions and the reading of the CI verdict are the plan's Decisions 5 to 8
(`docs/epics/agentic-dev-loop.md`); among the skills they are written down only here.

## Preconditions

```bash
gh api user --jq .login          # must print peter-christofer-bot
cd ~/agent-workspace/TrailMetrics
git fetch origin && git switch main && git pull --ff-only
git status --porcelain           # must be empty
```

Anything else (another login or clone, a dirty tree, a pull that can't fast-forward): stop
and report. If the previous run's PR has been merged, do the after-merge cleanup first.

A run whose gate will run the iOS steps needs the git-ignored iOS secrets config (README
"iOS", step 2) in the clone. The gate checks that it exists and stops at once if it is
missing; the agent never reads or creates it, and stops and reports instead.

## One task per run

A run ends when its PR is open and reported (Trial mode) or merged (after the trial). The
next task is a new run; the human clears the session between runs.

## 1. Pick

```bash
scripts/check-board.sh --next
```

- An epic or `figma-design-system`: don't code. Write the plan for the human to approve
  (`tm-pr-workflow`, "Board", rule 0) and stop.
- A record that is unclear, or whose Done when contradicts the code: stop and report.
- Otherwise the record is the task. Its Problem and Done when, verbatim, are the `TASK` text
  for the reviewer.

## 2. Implement

Follow `tm-pr-workflow` from "Before starting" on: branch prefix and name, commits with
`git commit -F <file>`, Boundaries, "Docs follow the code you changed", the "Board" rules,
and the record deleted in the last commit. Load the code skills for the paths you touch.
Scope is the record's Done when and nothing else.

## 3. Protected paths

```bash
scripts/check-protected-paths.sh --base "$(git merge-base HEAD origin/main)"
```

A task may touch protected paths if its record says so; the PR is then the human's to merge
(say so in the report). Never touch a protected path as a side effect.

## 4. Local review

Run the `pr-reviewer` on the final HEAD as `tm-pr-review`, "Orchestrator's part" describes,
and record the verdict.

- `APPROVE`: continue.
- `CHANGES`, or blocking findings under `ESCALATE_TO_HUMAN`: fix them as a new commit and
  review again. That is one review fix attempt. The budget is **2 review fix attempts per
  PR**, separate from the gate's 2 fix attempts (`tm-pr-workflow`, "Retry budget"). If the
  third review still has a blocking finding: stop, don't push, report the findings.
- Notes alone never trigger another round.
- `ESCALATE_TO_HUMAN` with no blocking findings: continue; the human decides.
- `NO_VERDICT` is never recorded: fix the cause and ask again. Environment problems are not
  attempts.

## 5. Gate, push, PR

Run `scripts/pre-push-check.sh` until green within the retry budget, then push and open the
PR with `gh pr create --base main --body-file <file>` (`tm-pr-workflow`, "Tier 1", "Push and
PR", "PR description"). A new commit needs a fresh review and a fresh gate run.

If the diff touches `.github/workflows/`, you can't push it (the machine token has no
`workflow` scope, Decision 1). Stop after the gate, write the PR description to
`~/agent-workspace/pr-body-<branch-slug>.md` and hand over to the human.

## 6. After the PR is open

```bash
gh pr checks <N> --watch         # never cancel anything
```

Then report. If a check is red after a green gate, don't iterate against CI and don't
re-run it on your own: report the run URL, the failing step and test, and whether the diff
touches the failing area, then wait for the human. A red check on a PR that changes nothing
related is likely a flake, but the human decides about a re-run.

## 7. Reading the CI verdict

The check's conclusion is green for both `APPROVE` and `ESCALATE_TO_HUMAN`, so the verdict
is read from its annotation (Decision 8). The check run `Review — pr-reviewer` for the head
SHA carries exactly one annotation whose title is `Review — pr-reviewer` (other annotations,
such as runner notices, have other titles).

```bash
N=<PR number>
SHA="$(gh pr view "$N" --json headRefOid --jq .headRefOid)"
D="$(mktemp -d)"
gh api "repos/{owner}/{repo}/commits/$SHA/check-runs?check_name=Review%20%E2%80%94%20pr-reviewer&filter=latest" > "$D/runs.json"
RUN_ID="$(jq -r --arg sha "$SHA" '[.check_runs[] | select(.name == "Review — pr-reviewer" and .head_sha == $sha)] | if length == 1 then .[0].id else empty end' "$D/runs.json")"
if [ -n "$RUN_ID" ]; then
  gh api "repos/{owner}/{repo}/check-runs/$RUN_ID/annotations?per_page=100" > "$D/annotations.json"
else
  echo '[]' > "$D/annotations.json"
fi
jq -n -r --arg sha "$SHA" --slurpfile runs "$D/runs.json" --slurpfile ann "$D/annotations.json" '
  ($runs[0].check_runs | map(select(.name == "Review — pr-reviewer" and .head_sha == $sha))) as $r
  | if ($r | length) != 1 then "NOT_APPROVE: \($r | length) check runs for \($sha)"
    elif $r[0].status != "completed" then "NOT_APPROVE: check run is \($r[0].status)"
    else ($ann[0] | map(select(.title == "Review — pr-reviewer"))) as $a
    | if ($a | length) != 1 then "NOT_APPROVE: \($a | length) annotations with that title"
      elif ($a[0].blob_href | tostring | contains("/blob/\($sha)/") | not) then "NOT_APPROVE: annotation is not for \($sha)"
      elif $a[0].annotation_level == "notice" and ($a[0].message | startswith("APPROVE.")) then "APPROVE"
      elif $a[0].annotation_level == "warning" and ($a[0].message | startswith("ESCALATE_TO_HUMAN:")) then "ESCALATE_TO_HUMAN"
      elif $a[0].annotation_level == "failure" and ($a[0].message | startswith("CHANGES:")) then "CHANGES"
      else "NOT_APPROVE: level \($a[0].annotation_level) and message \($a[0].message | .[0:30]) disagree"
      end
    end'
jq '.[] | select(.title == "Review — pr-reviewer") | {annotation_level, title, message}' "$D/annotations.json"
```

The mapping: level `notice` with a message starting `APPROVE.` = `APPROVE`; `warning` with
a message starting `ESCALATE_TO_HUMAN:` = `ESCALATE_TO_HUMAN`; `failure` with a message
starting `CHANGES:` = `CHANGES`. Anything else is **not** `APPROVE`: no annotation with that
title, more than one, a level and message that disagree, a check run that is not completed,
or an annotation from a different SHA. Fail closed: only the exact output `APPROVE` counts.

Don't use `gh pr view --json reviewRequests`: the machine token lacks `read:org`. Use
`reviewDecision` (`gh pr view <N> --json reviewDecision`) or the REST API
(`gh api repos/{owner}/{repo}/pulls/<N>/requested_reviewers`).

## 8. Merge conditions

Check each one, in order, for the PR's current head SHA. All must hold:

1. Both required checks are green on the head SHA: `Android — Lint, Detekt, Tests, Build`
   and `iOS — SwiftLint, Build` (names exactly).
2. The PR head is a branch of this repository (`isCrossRepository` is `false`).
3. The author is `peter-christofer-bot`.
4. The CI annotation says `APPROVE` for that head SHA (section 7).
5. The local reviewer's recorded verdict for that SHA is `APPROVE`.
6. The PR touches no protected path. For a subtask PR into an epic branch this condition is
   replaced by: the plan's `allowed_paths` for that subtask cover every changed path.

```bash
gh api "repos/{owner}/{repo}/commits/$SHA/check-runs?filter=latest" \
  --jq '.check_runs[] | select(.name == "Android — Lint, Detekt, Tests, Build" or .name == "iOS — SwiftLint, Build") | [.name, .status, .conclusion] | @tsv'
gh pr view "$N" --json isCrossRepository,author,headRefOid,baseRefName,state
cat "$(git rev-parse --path-format=absolute --git-path .review-verdict)"   # "<SHA> APPROVE"
git fetch origin
# condition 6, PR against main:
scripts/check-protected-paths.sh --base "$(git merge-base origin/main "$SHA")"
# condition 6, subtask PR into an epic branch: every changed path must be in the subtask's allowed_paths
git diff --name-only "$(git merge-base "origin/<epic branch>" "$SHA")" "$SHA"
scripts/check-protected-paths.sh --base "$(git merge-base "origin/<epic branch>" "$SHA")"
```

The base is the merge-base with the branch the PR targets: `origin/main` for a PR against
`main`, the epic branch for a subtask PR. Run the protected-path check with the PR branch
checked out at `$SHA`. If every condition holds, the merge command is:

```bash
gh pr merge <N> --squash --match-head-commit <SHA>
```

GitHub's "Allow auto-merge" setting stays off: never enable it and never use
`gh pr merge --auto`. The epic PR into `main` is never the agent's: only on the human's
explicit command, with `gh pr merge --match-head-commit <tested SHA>`. If the epic touches
a protected path, the human also approves the PR on GitHub (Decision 5).

## Trial mode

Until S6 documents otherwise, **no agent merges any PR**, including subtask PRs into an
epic branch. Instead, once the checks are done, post one PR comment on every PR, including
PRs that touch a protected path (condition 6 is then "no", so "would auto-merge: no")
(`gh pr comment <N> --body-file <file>`):

```
Trial check (not acted on)

1. Required checks green on <SHA>: yes|no
2. Head is a branch of this repository: yes|no
3. Author is peter-christofer-bot: yes|no
4. CI annotation APPROVE: yes|no (<title>, <level>, "<first words of message>")
5. Local verdict APPROVE for <SHA>: yes|no
6. No protected path: yes|no

would auto-merge: yes|no
Counts toward the trial: yes|no
```

"Counts toward the trial" is "no" whenever the PR touches a protected path, or when its
review check never produced a valid report (Decision 7).

The human's decision on that PR is compared with it to count the trial of 5 consecutive PRs
that touch no protected path; any disagreement restarts the count (Decision 7).

A PR whose first review report was malformed (its first line not a verdict) and whose
automatic retry, or a human re-run of the failed check, produced a valid report counts
normally, by the final valid verdict (section 7 reads the latest run) compared with the
human's decision. A PR whose check never produced a valid report (section 7 prints
`NOT_APPROVE: ...`, and the annotation's message starts with none of `APPROVE.`,
`ESCALATE_TO_HUMAN:` and `CHANGES:`) does not count toward the trial and is not a
disagreement.

## After-merge cleanup

At the start of the next run, or right after the agent's own merge (Decision 6):

```bash
gh pr view <N> --json state      # must be MERGED
git switch main && git pull --ff-only
git branch -D <branch>           # squash merges are not "merged" for git
git fetch --prune
```

GitHub deletes the remote branch itself ("Automatically delete head branches" is on).

## Stop and report

- The identity is wrong, or an environment failure.
- The gate's retry budget or the review fix budget is exhausted.
- The record is an epic or unclear.
- A protected-path change the task did not call for.
- CI red after a green gate.
- Anything that would need a force-push, an amend, a cancelled run or reading a credential.

## Never

- Push to `main`, force-push or amend, or cancel a CI run.
- Enable auto-merge, change repository settings, or edit a protected path outside the task.
- Read other credentials. The deny rules in `.claude/settings.json` are best effort, not a
  wall: don't try to get around them.
- Merge in Trial mode.
