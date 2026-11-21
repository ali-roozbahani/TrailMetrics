---
name: tm-pr-workflow
description: Use for every TrailMetrics task that will end in a commit, push or PR — creating the branch, running the Tier 1 local gate (scripts/pre-push-check.sh), the 2-attempt retry budget, commit message and PR title format, what the PR description must contain, Tier 2 (the automated test for each user-visible behavior, or a human check with its reason), and the standing boundaries (files not to touch as a side effect, no new dependencies, no module-boundary crossing, stating assumptions, following the task's reference pattern). Not for how to write the code itself (see tm-android, tm-ios, tm-kmp-shared, tm-testing) or for planning multi-agent epics.
---

# TrailMetrics PR workflow

This skill is the source of truth for the agent workflow (it replaced the retired
`docs/workflow/coding_agent_workflow.md` and the "Commit, branch & PR discipline" section of
`shared_conventions.md`). It records both the rules and what the repo, the gate script, the
push hook and recent PRs actually do. Where they differ, the repo wins for "what is
enforced", the rules here win for "what the agent should do". Multi-agent epics are covered
in `epic-orchestration`.

The task prompt only says *what* to do. Everything below applies to every task without the
prompt restating it, including committing, pushing and opening the PR: the agent does
those on its own initiative once Tier 1 passes.

## Topic files

Read each file when the task reaches its topic, not before; a reviewer reads it for a diff that touches the topic.
Section headings are unchanged, so a reference to `tm-pr-workflow`, "<heading>", is found in this file or in the file
named here. The detail files that already existed (`gate-steps.md`, `gate-enforcement.md`, `tier2.md`, `board.md`,
`flake-log.md`, `pr-description-extras.md`, `test-counts.md`, `task-template.md`, `after-pr-open.md`,
`enforcement-and-history.md`) are named where this file points to them.

| File | Read it when |
|---|---|
| `commits-push-pr.md` ("Commits", "Push and PR", "PR description") | before the first commit of a task: the commit and PR title format, the push and PR commands, the headings of the PR description and the trailer |
| `retry-budget.md` ("Retry budget (2 fix attempts)") | the gate is red, or a fix of the gate is being made: what counts as an attempt, what does not, when to stop |
| `dependency-bump.md` ("Dependency version bump") | a version in `gradle/libs.versions.toml` or an SPM dependency changes |


## Before starting

Every run starts with these steps, for a named task and a board pick alike:

```bash
gh api user --jq .login          # must print peter-christofer-bot
cd ~/agent-workspace/TrailMetrics
git status --porcelain           # must be empty
git fetch --prune origin && git switch main && git pull --ff-only
scripts/prune-merged-branches.sh # deletes the local branches whose PR is merged
scripts/main-ci-status.sh --recent 5   # the last 5 push runs on main, newest first
scripts/main-ui-run.sh --status        # the last full UI run of main, and whether one is due
```

- Anything else (another login or clone, a dirty tree, a pull that can't fast-forward): stop
  and report.
- `scripts/prune-merged-branches.sh` deletes every local branch whose PR is `MERGED` and keeps
  the rest; the `OPEN #n` and `NO_PR` lines it prints go in the report. A hook refuses to create a
  new branch until `scripts/prune-merged-branches.sh --check` exits 0 (exit 4 is unknown: report
  it, don't bypass). GitHub deletes the remote branch itself ("Automatically delete head
  branches" is on).
- `scripts/main-ui-run.sh --status` prints the last full UI run of both platforms on `main` (its SHA, result and
  time) and `DUE <reason>` or `NOT_DUE <reason>`. `DUE` is reported first; with an empty queue run
  `scripts/main-ui-run.sh --auto` before the task (`tm-agent-loop`, section 9), so a run that was due when the
  last session ended is not forgotten. It never fails the start of a task.
- `scripts/main-ci-status.sh --recent 5` prints, newest first, one line per run (run id, merge SHA,
  PR number or `-`, conclusion or `running`, failed job names) and `RECENT green=<n> red=<n>
  running=<n> unverified=<n> unacknowledged-red=<n>`; its exit code is that of the newest run (0 green, 1 red,
  3 running, 5 unverified, 4 unknown). It covers merges the agent did not make. Put the output first in the report.
  - `running`: skip it, say so in the report, go on. The next task looks again.
  - `unverified` (a line `cancelled unverified`, exit 5): the commit's push run was cancelled, so it is neither green nor red and
    nothing re-runs `main`. Report it with what verifies the commit instead: a green full UI run on that very commit
    (`scripts/main-ui-run.sh --status` prints the last one and its SHA) or the next push run of `main`, which tests a tree that holds
    it (a line `cancelled verified-by <run id>` says a later green run exists). It is not a stop, and nothing is re-run on `main`;
    the owner decides whether to re-run it. Who cancelled it is not known from the run: do not assume a tool of this session did.
  - All `success`: say nothing but the summary line.
  - An unacknowledged `failure`: STOP before any edit. Report the PR and merge SHA, the failed jobs,
    your classification from reading the log as data (`defect`, a flake already in `CI_FLAKES.md`,
    `infra` or `unknown`, with the evidence line) and your recommended way out; wait for the
    owner. Never fix or re-run anything on `main`.
  - The owner's "go on" after such a report is the only trigger for
    `scripts/main-ci-status.sh --ack <run id>`; it stores the highest acknowledged run id in
    `~/agent-workspace/main-ci-ack` and never lowers it. Runs at or below it are not unacknowledged.
  A `MERGED-in-worktree` line of `prune-merged-branches.sh` also goes in the report, with its path;
  the owner removes the worktree.
- Create the task's branch from this local `main` (see "Branching").

- Read `docs/architecture/OVERVIEW.md`, the `README.md` of every module the task touches,
  and `LEARNINGS.md` for known KMP/Xcode/Gradle gotchas.
- Load the code skill(s) for the modules touched (`tm-kmp-shared`, `tm-android`, `tm-ios`,
  `tm-testing`) as well as this one, and `tm-robustness` for any Kotlin or Swift change.
- If the task names a board record, read `BOARD.md` first (see "Board").
- Task prompts follow the standard template in `task-template.md`. Treat the "should not
  change" part of `Scope` as a hard limit.

## Branching

- One feature or fix per branch.
- Create and check out the branch **before the first edit**. Never leave changes on the
  branch you started from, and never commit to `main`.
- Name: `<type>/<slug>`, where type is one of exactly three prefixes:
  - `feature/<slug>`: new functionality
  - `bugfix/<slug>`: fixing a defect
  - `chore/<slug>`: tooling, docs, config, CI, dependency bumps, refactors with no
    behavior change
- Use the name from the task's `Branch:` line. If it uses any other prefix (`docs/`, `ci/`,
  `fix/`, ...), switch to the closest allowed one and say so under "Assumptions" in the PR.
  Precedent: #35 was asked for `docs/...` and used `chore/...`.
- Branch from the local `main` that "Before starting" left equal to `origin/main`, never from
  `origin/main` directly, unless the task names a different base or the branch is a queue entry
  built on its parent's local branch (`tm-agent-loop`, section 9).
- Slug: lowercase, hyphenated, describes the change (`chore/fix-gate-test-coverage`,
  `bugfix/route-reset-profile-refetch`).

## Tier 1: the local gate (agent's job)

`scripts/pre-push-check.sh` must exit 0 before any push. The script is the description of the
gate: its header comment, its output (one line per step that ran, with the path of that step's full
log under `~/agent-workspace/gate-logs/`; a failed step also prints its failure block) and the `--self-test`
option of each `scripts/check-*.sh` script say what is checked, so read them rather than a list
here. Run the script itself, not a hand-picked command.

The steps, one bullet each, are in `gate-steps.md`; read it before the first gate run. Headlines: `scripts/classify-changes.sh` decides `light` or full, and a skipped step is not a pass (the PR's Tier 1 says which steps ran and why the rest did not); a new script's `--self-test` goes on one of the two lists; a failing step fails the gate, which is then fixed within the retry budget; never pass a secret on an `xcodebuild` command line, and never read, print, create or commit the iOS secrets config; one heavy run at a time, through `scripts/heavy-run.sh`; `koverVerify`, the Room schema check and the shallow-clone check are gate steps; the local `pr-reviewer` verdict for HEAD must be recorded before every push, or the push hook refuses it.

How it is enforced (the full text, with the exact shapes of the push and PR commands, is in `gate-enforcement.md`; read it before the first commit):

- The `PreToolUse` hook blocks the push and the PR creation unless `.git/.pre-push-check-passed` is newer than the last commit: always **commit → run the gate → push**, and a new commit needs a fresh gate run.
- The gate reads **committed** changes only. The hooks match on command text, so pass long text through a file (`git commit -F`, `--body-file`); the deny rules match the whole command text too (a command never names `local.properties`, `.env` or `Secrets.xcconfig`).
- Run the gate as `scripts/pre-push-check.sh` alone; push the branch with an absolute `cd` or `git -C` when not in the clone; run `scripts/prune-merged-branches.sh` as its own command before creating a branch.
- `./gradlew test` on its own runs zero tests; use the gate script and read counts from `allTests`.
- **Coverage ratchet.** A PR that adds tests to a module with a Kover floor raises that floor
  (its entry in `config/kover-floors.properties`, which its `build.gradle.kts` reads) in the
  same PR, to the module's measured line coverage
  (`./gradlew :<module>:koverLog`) minus 1 to 2 points, rounded down. Verify it once: set it 1
  point above the measured value, see `koverVerify` fail for that module, restore. Never lower
  a floor to make a PR pass. If coverage barely moves because the remaining code needs
  infrastructure that isn't available, say so in the PR instead of padding tests.
  `scripts/check-kover-floors.sh` (gate and CI) fails when a floor is lower than on the base,
  when a module whose `build.gradle.kts` reads the file has no entry, when an entry has no
  such module, and when a floor's entry is gone while the module that held it still exists.
  Lowering a floor is not supported by the mechanism: it needs a human PR that
  changes the script. A new module's first floor is a new entry plus the same read in its
  `build.gradle.kts`.
- A task is not done until Tier 1 has been run **and** its result reported in the PR.
- **A result is read from the check, not from what started it.** The result of a gate run is the line the gate itself prints
  last, and the record it writes for exactly the commit it checked. The exit code of a wrapper, a background task or a pipe
  around it is not the result, and a line a wrapper wrote is not the gate's. A step that acts on a green result (a merge, a push)
  names the commit it acts on and refuses without the record for exactly that commit. Why: a wrapper reports its own last
  command, so a red gate can look green. Example and mechanism: `LEARNINGS.md`, "The first epic run: a gate result read from a wrapper".

## Tier 2: what automated tests cannot show

The user-visible behavior of a change is validated by automated tests, not by a human on a device. A human check is listed only for one of three reasons: no automated test can observe it; a test seam or target that does not exist yet, tracked by a queued PR or a board record the PR names; the single final smoke check of a finished end-to-end feature. Each human check gives the behavior, the reason and the exact steps; a docs-, test-, CI- or skill-only change says plainly that nothing user-visible changes. The full text, with what no test can observe in this repo, is in `tier2.md`.

## Boundaries

- Never change a protected path as a side effect of an unrelated task. Protected paths
  change only through their own explicitly scoped task and review. The single source of
  truth for which paths are protected is `.github/CODEOWNERS`; there is no list here.
  `scripts/check-protected-paths.sh` classifies a diff from it (`--files <path>...` for
  single paths). If a protected file is wrong and not of this task's subject (see "Docs
  follow the code you changed"), list it under "Follow-ups" instead and queue it as an owner
  entry ("Board", rule 1; #32, #33, #34 and #37 reported such files).
  The five reference skills (`tm-ios`, `tm-android`, `tm-kmp-shared`, `tm-testing`, `tm-robustness`) are not
  protected (their folders have ownerless lines in CODEOWNERS, so every file in them is open),
  so an agent may edit them in a task that calls for it; the reviewer judges that diff like any other, and the
  rule-change signal (`tm-pr-review` item 10) escalates any removed or rewritten rule line.
- An agent never merges a PR that touches a protected path. The human merges those. The epic PR into
  `main` is always the human's; the subtasks of an epic are not PRs (`epic-orchestration`).
- **Docs follow the code you changed.** Before the final gate run, sweep: search the repo
  (code, skills, docs, comments, CODEOWNERS, scripts, CI, `BOARD.md` records) for the names,
  paths, slugs, counts and behaviours this task touches or makes stale, and check each hit.
  Fix in the same PR every hit of the task's own subject: a line now wrong because of the
  change, or the CI, gate or CODEOWNERS wiring of a script or file the change adds or
  changes. That is part of the task, not a side effect, so it needs no separate
  authorization, a protected path (a workflow file, which the agent pushes as a PR) included; the PR
  is then the human's to merge. The bound is 10 changed lines in 2 files per hit and 30
  lines for all hits. The authorization never covers changing a rule's content or
  strength, adding a rule or weakening a check. Drift about code this task didn't change,
  or a hit beyond the bound, is not fixed here: it goes where "Board", rule 1 says (a queued
  PR of its own, or a `BOARD.md` record) and is listed under "Drift found (not fixed)" in the
  PR description, with the line and what the code actually does.
  - A sentence that states what the code does today (a "today", "still", "not yet", "for now" or
    "currently" statement) holds none of these words: must, never, always, do not, don't, required,
    forbidden, only, at most, at least. The rule it relates to is its own sentence next to it. Why:
    a line that mixes the two is listed by the rule-change signal (`scripts/check-skill-rule-changes.sh`)
    each time the statement is brought up to date, although no rule changed.
- Never add a third-party dependency (Gradle, SPM or otherwise) unless the task's Scope
  names it. If the task can't be done without one, stop and say so. #34 hit this and
  reported it rather than adding `sqlite-bundled`'s JVM artifact.
- A third-party project's `gradlew`, scripts, build files and plugins are code. Run or build them only in a
  scratch clone, and only after reading them.
- Never cross a module boundary listed in `tm-kmp-shared`. If
  the task seems to need it, stop and report. Don't work around it.
- Never call a deprecated API (details per platform in `tm-android` / `tm-ios`).
- If the docs or conventions are ambiguous or silent on something the task needs, pick the
  most conservative reading and **state it** under "Assumptions". Never choose silently.
- Follow the structure, naming and pattern of the reference that the task's `Context`
  points to. The exception is a reference that hasn't been migrated to its target
  pattern yet. Then follow the target pattern and say so. (All four Android ViewModels
  are on MVI since #54; `tm-android` lists the deviations that remain.)

## Board

`BOARD.md` is the backlog of what the agent does not do on its own. The seven rules (0 picking work, 1 add, 2 delete, 3 report, 4 no board-only PRs, 5 epics, 6 leave other records alone) are in `board.md`; read it before touching `BOARD.md` or leaving anything for later. In short: a follow-up the agent can do is a queue entry and a PR of its own, never a record; a record only for an owner decision or design, an epic, an item the queue refuses, a sweep finding or a flake at count 3; the PR that resolves a record deletes it in its own commit; every PR description carries a `Board:` line.

## Flake log

`CI_FLAKES.md` logs CI flakes and local UI flakes; the agent edits it. The rules (one entry per signature, local UI flakes, where the update goes, escalation at count 3, `fixed (unverified)` and `fixed`) are in `flake-log.md`; read it before logging a flake or fixing one.

## After the PR is open

The agent continues with `tm-agent-loop`, sections 6 to 8 (`watching-ci.md`, `merge.md`), and posts the "Merge check" comment on
every PR. The human's part that follows, for context, is in `after-pr-open.md`.

Review comments turn into new commits on the same branch, each through the gate again.
Answer them in the PR (see #35's comment summarising its second commit) rather than
silently force-pushing.

## Where enforcement and history differ from the rules

What the repo, CI and history actually do where they differ from the rules above (branch
protection, the review check, CI's triggers and iOS jobs, commit and branch history) is in
`enforcement-and-history.md`. One decision stays here because it is a rule for a future change:

- **CI's `xcodebuild` steps don't scrub the environment or filter the log; the gate does.**
  The gate removes secret-looking variables (`scripts/scrub-env.sh`) and filters the
  `export` dump out of the `xcodebuild` output (`scripts/filter-xcode-log.sh`). CI's
  `xcodebuild` steps do neither. Decided 2026-10-18 to leave CI as it is: the iOS jobs hold
  no secret (`ci.yml` references no `secrets.`, and the generated configuration file
  contains a placeholder key only), and GitHub masks real secrets in logs. If a secret is
  ever given to an iOS job, scrubbing and filtering become required first, with
  `set -o pipefail` in the step, because the default macOS `run:` shell has no pipefail.
