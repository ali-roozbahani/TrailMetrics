# Where enforcement and history differ from the rules

Read from `SKILL.md`, "Where enforcement and history differ from the rules". The rules are there; this file holds what the repo, CI and history actually do, as recorded.

- **Branch protection enforces CI and code owner review.** As reported by the human on
  2026-10-18 (the machine token can't read the settings): `main` requires a PR and
  `enforce_admins` is on, so a direct push to `main` is rejected. Review from code owners is
  required, so a PR that touches an owned path in `.github/CODEOWNERS` can't merge without
  the code owner's approval, and stale approvals are dismissed when new commits are pushed.
  Branches must be up to date before merging. The required checks are
  `Android — Lint, Detekt, Tests, Build`, `iOS — all stages` (the `ios` aggregator job),
  `Repo tooling — policy checks and script self-tests` (the `tooling` job)
  and `Review — pr-reviewer`, so a PR can't merge with red CI or while it's behind `main`.
  "Require approvals" is off (approval count **0**), so a PR that touches no owned path
  needs no approval. #30–#37 were all merged with no review, before code owner review was
  required. The Android and iOS checks were required before #38 merged.
- **The review check is required, but green is not approval.** `Review — pr-reviewer`
  (`.github/workflows/pr-review.yml`) is green for both `APPROVE` and `ESCALATE_TO_HUMAN`;
  the verdict is read from its annotation (`tm-agent-loop`, section 7).
  The annotation holds the verdict and the count of `[important]` findings; the report is the workflow
  artifact `pr-review-report` of that run (kept 7 days), which the agent downloads with
  `gh run download` after `CHANGES`, blocking findings or a count above zero (`tm-agent-loop`,
  section 7).
- **The protected-paths check runs in the gate and in CI** (the "Protected paths check"
  step of CI's `tooling` job).
- **"Automatically delete head branches" is enabled.** GitHub deletes a PR's remote branch
  when it merges; the local branch is the agent's to delete ("Before starting").
- **The gate is a Claude Code hook, not a git hook.** It is a `PreToolUse` hook, so it
  only gates pushes made from a Claude Code session. A push from a terminal skips it.
- **CI doesn't mirror the gate exactly.** CI's heavy steps run unless
  `scripts/classify-changes.sh` decides `light` (no changed file can affect the Android or iOS
  build or tests: docs, skills, tooling scripts outside its HEAVY_SCRIPTS list; pushes always run
  everything). Unlike the gate, CI's iOS jobs have no iOS path filter: on a non-`light` PR
  `ios-main` runs SwiftLint, the iOS build and the iOS simulator tests, and `ios-build-ui` and
  `ios-ui` build and run the UI tests, even when the gate skipped its iOS steps. For a diff in the
  UI scope the gate builds the `uitest` variant and runs ONE smoke UI test
  (`DetailsFailedDeleteUITests`); CI builds the variant once in `ios-build-ui` and runs ALL UI tests
  in `ios-ui`. So an `iosApp/` problem that already existed on `main` can make CI red on an
  unrelated Android-only PR. CI's `android-build` job runs on Ubuntu, where the iOS simulator tests are
  skipped; they run in `ios-main`, `domain`'s and `data`'s since #34, `shared`'s since S3 of
  `protected-paths-review-2`. The `ios` job is the aggregator that carries the required check
  name: it runs no build step and is green only when `ios-plan`, `ios-build-ui`, `ios-ui` and
  `ios-main` passed, or the three macOS jobs were skipped on a `light` decision.
- **CI only runs on push for `main` and `feature/epic/**`.** `ci.yml`'s push trigger doesn't
  include `bugfix/**` or `chore/**`, so those branches get CI only once the PR is open.
- **Commit types have been used inconsistently.** The retired docs listed only
  `feat`/`fix`/`refactor`/`build`/`docs`/`test`. `chore` is the most-used type since #30,
  and the same kind of change has been typed differently (`chore(ci)` in #33,
  `build(ci)` in #34).
- **The PR description checklist is only partly followed.** #32, #34 and #35 have all four
  items. #33, #36 and #37 have no "Skills/docs followed" and no Tier 2 line, and #30/#31
  follow neither. This skill makes all four headings mandatory.
- **Branch prefixes were looser before #30.** `docs/` (#10, #27), `ci/` (#5) and `phase-*`
  (#1, #2) branches exist in history. Since #30 every branch is `feature/`, `bugfix/` or
  `chore/`.
- **Three commits reached `main` without a PR** (`0add288`, `0ff3ccc`, `6c37a62`, all on
  2026-09-19). That was before #30 turned on the current protection. Every change since
  has gone through a PR.
- **The Boundaries list is wider than `CLAUDE.md`'s.** `CLAUDE.md` lists
  `docs/architecture`, CI, lint config and itself. It doesn't list the gate script, the
  hook, `.claude/settings.json` or the skills. This skill adds those (assumption: they're
  as load-bearing as CI config).
- **The retry budget was never defined precisely.** The retired workflow doc said
  "2 fix attempts" without defining an attempt or saying whether review rounds and
  follow-up PRs count. The definition above is this skill's reading. GitHub doesn't record
  local gate failures, so recent PRs can't show how often the budget is actually hit.
