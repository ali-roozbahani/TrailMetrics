# Epic branch protection: reasons and ruleset

Read from `SKILL.md`, "Protection". The rules are there; this file holds the reasons for one ruleset and the ruleset itself.

## Why one ruleset

- Subtask PRs merge into the epic branch, not `main`. Without required checks, a red
  subtask can land there, and the problem only shows up when the epic's PR to `main`
  fails. By then it's mixed in with every other subtask.
- **Strict** matters most here. Parallel subtasks (S2 ∥ S3) each go green against the
  epic branch as it was when they started. Strict forces the second one to merge in the
  first and go green again before it can merge. That's the only point where the
  *combination* gets tested before the final PR.
- The branch is per-epic, but a ruleset on `refs/heads/feature/epic/*` covers every
  future epic branch the moment it's created. There's nothing to remember per epic, and
  no window where the branch is unprotected. The repo is public, so rulesets are
  available.
- The CI jobs behind the four checks run on every PR (no path filters), so requiring all four
  checks can't leave a PR stuck waiting for a check that never runs.

## The ruleset

```json
{
  "name": "Epic integration branches",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/feature/epic/*"], "exclude": [] } },
  "rules": [
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false, "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": true,
        "required_status_checks": [
          { "context": "Android — all stages", "integration_id": 15368 },
          { "context": "iOS — all stages", "integration_id": 15368 },
          { "context": "Repo tooling — policy checks and script self-tests", "integration_id": 15368 },
          { "context": "Review — pr-reviewer", "integration_id": 15368 } ] } },
    { "type": "non_fast_forward" }
  ]
}
```

`do_not_enforce_on_create: true` is explicit because GitHub defaults it to `false`, which
rejects creating the branch unless its base commit already has all four checks green.

Apply it with `gh api -X POST repos/ali-roozbahani/TrailMetrics/rulesets --input <file>`,
or through Settings → Rules. There are no bypass actors, which matches `enforce_admins` on
`main`. It deliberately has no `deletion` rule, so the human can delete the branch after
the epic lands. It has no `creation` rule, so the branch can be created by a plain push.
