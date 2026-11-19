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

## Pre-flight check

Run by the orchestrator before it creates an epic branch (`running-an-epic.md`, step 1.5). It reads the ruleset and compares it
with the CI workflows; it changes nothing. The check names a ruleset requires are the names of CI jobs: a name that no job has
leaves the check waiting for ever, and every PR into the epic branch is blocked (the first version of the owner's ruleset required
`Android — Lint, Detekt, Tests, Build`, a name from before the job was renamed, and lacked the tooling check; it was found by hand).

```bash
D="$(mktemp -d)"; REPO=ali-roozbahani/TrailMetrics
ID="$(gh api repos/$REPO/rulesets --jq '[.[] | select(.name=="Epic integration branches" and .enforcement=="active")][0].id')"
[ -n "$ID" ] && [ "$ID" != null ] || echo "NO ACTIVE RULESET named Epic integration branches"
gh api repos/$REPO/rulesets/$ID > "$D/ruleset.json"
# covers the epic branches and has no bypass actor
jq -e '.conditions.ref_name.include == ["refs/heads/feature/epic/*"] and (.bypass_actors // []) == []' "$D/ruleset.json"
# pull request required, force pushes blocked, checks required and up to date, no check required on creation
jq -e '[.rules[].type] | (index("pull_request") != null and index("required_status_checks") != null and index("non_fast_forward") != null)' "$D/ruleset.json"
jq -e '.rules[] | select(.type=="required_status_checks") | .parameters | (.strict_required_status_checks_policy == true and .do_not_enforce_on_create == true)' "$D/ruleset.json"
# the required names, from GitHub Actions (integration 15368), against the four names the repo waits for
jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[] | select(.integration_id == 15368) | .context' "$D/ruleset.json" | sort > "$D/have.txt"
sed -n '/^REQUIRED_CHECKS="/,/"$/p' scripts/wait-for-checks.sh | sed 's/^REQUIRED_CHECKS="//; s/"$//' | sort > "$D/want.txt"
# every wanted name is the name of a job in the workflows that run for a PR into an epic branch
while IFS= read -r name; do grep -q -F "    name: $name" .github/workflows/ci.yml .github/workflows/pr-review.yml || echo "NO JOB NAMED: $name"; done < "$D/want.txt"
diff "$D/have.txt" "$D/want.txt" && echo "required checks match"
# the workflows run for a pull request whose base is an epic branch
grep -n "branches:" .github/workflows/ci.yml
```

Every `jq -e` prints `true`, the loop prints nothing, `diff` prints nothing and `ci.yml`'s `pull_request` branches include `'feature/**'`: the ruleset is right. Anything
else is a stop: report the exact output and the one thing the owner has to change in the ruleset (Settings, Rules); the owner edits it, never the orchestrator.
When the job names change later, `REQUIRED_CHECKS` of `scripts/wait-for-checks.sh` (which its self-test and `main`'s protection already follow) and the ruleset change
in the same PR or the same hour, and this check is what notices when they do not.

