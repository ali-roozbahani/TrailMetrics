# Retry budget (2 fix attempts)

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the section "Retry budget (2 fix attempts)". The rules are unchanged; they are still cited as `tm-pr-workflow`, "Retry budget".

## Retry budget (2 fix attempts)

- One attempt = a change aimed at a gate failure, then a full re-run of
  `scripts/pre-push-check.sh`. The first run doesn't count. If the gate is still red after
  the second fix attempt (third run), **stop**: don't push, and report which step fails,
  the relevant output, and what each attempt changed. Then wait.
- Every stop-and-report, and the final report of a run, has the shape in `tm-agent-loop`, "Report".
- Environment failures are not attempts. Report them right away rather than working
  around them: SwiftLint not installed, no Xcode/simulator, Gradle daemon or network
  errors, a failure that reproduces on a clean `main`.
- Never "fix" a gate failure by editing lint/Detekt/SwiftLint config, adding
  `@Suppress`/`swiftlint:disable`, excluding a test or skipping a step. That trades a gate
  failure for a boundary violation (see "Boundaries", `SKILL.md`).
- The budget covers only the local gate loop. It does **not** cover:
  - Review feedback on an open PR. Each requested change is a new commit on the same
    branch, with its own gate run (#31 and #35 each got a second commit this way).
  - Follow-up PRs. #33 → #34 → #35 and #36 → #37 were chains where a PR's findings or a
    reviewer's correction led to a new, separately scoped task. None of them was a gate
    failure: all of #30–#37 were green in CI on the first run.
  - CI going red after a green local gate. That shouldn't happen (see "Where enforcement and history differ from the rules",
    `SKILL.md`). If it does, follow `tm-agent-loop`, section 6 (`watching-ci.md`) (a fix is a new commit through the
    gate, at most 2 such CI-fix rounds per PR; a flake is re-run once through the script)
    instead of iterating against CI.
