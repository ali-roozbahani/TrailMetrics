# Epic branch protection: none, and the pre-flight check

Read from `SKILL.md`, "Protection". The rule is there; this file holds the reasons and the check.

## Why there is no ruleset

The first version of this skill recommended a repository ruleset on `refs/heads/feature/epic/*` (a pull request required, four required checks, strict), so that subtask PRs
into the integration branch could not land red. The owner decided on 2026-11-19 that a subtask is not a PR (`running-an-epic.md`): the subtasks merge locally, the integration
branch is pushed once, and the one epic PR into `main` is guarded by `main`'s own protection. With the ruleset active, a fix pushed to the open epic PR after a red CI would be
refused, because the ruleset requires a pull request and passing checks for every update of the branch. So **no such ruleset may be active while an epic runs**. The owner deletes
it himself; the orchestrator never creates, edits or deletes a ruleset or a branch protection rule.

(The earlier ruleset had also been created with an Android check name that no longer existed, `Android — Lint, Detekt, Tests, Build`, and without the tooling check: a required name that no
job has blocks every PR for good. That risk is gone with the ruleset. It returns if a ruleset is ever made again: compare its required names with `REQUIRED_CHECKS` of
`scripts/wait-for-checks.sh` and with the job names in `ci.yml` and `pr-review.yml`.)

## Pre-flight check

Run by the orchestrator before it creates the integration branch (`running-an-epic.md`, step 1.5). It reads the rulesets and changes nothing.

```bash
D="$(mktemp -d)"; REPO=ali-roozbahani/TrailMetrics; SLUG=<slug>
gh api repos/$REPO/rulesets --jq '.[] | select(.enforcement=="active") | .id' > "$D/ids.txt"
while IFS= read -r id; do gh api repos/$REPO/rulesets/$id > "$D/r-$id.json"; done < "$D/ids.txt"
python3 -I - "$D" "refs/heads/feature/epic/$SLUG" <<'PY'
import glob, json, re, sys
d, ref = sys.argv[1], sys.argv[2]
def rx(g):  # a GitHub ref pattern: ** crosses slashes, * does not
    return re.compile('^' + re.escape(g).replace(r'\*\*', '.*').replace(r'\*', '[^/]*') + '$')
bad = []
for f in sorted(glob.glob(d + '/r-*.json')):
    r = json.load(open(f))
    if r.get('target') != 'branch' or r.get('enforcement') != 'active':
        continue
    c = r.get('conditions', {}).get('ref_name', {})
    inc = c.get('include', []); exc = c.get('exclude', [])
    hit = any(g in ('~ALL',) or rx(g).match(ref) for g in inc) and not any(rx(g).match(ref) for g in exc)
    kinds = [x['type'] for x in r.get('rules', []) if x['type'] in ('pull_request', 'required_status_checks', 'update', 'required_linear_history', 'non_fast_forward')]
    if hit and kinds:
        bad.append((r['id'], r['name'], kinds))
for b in bad:
    print('RULESET APPLIES:', b)
print('ok' if not bad else 'STOP: the owner deletes the ruleset above')
PY
```

The last line is `ok` when no active branch ruleset applies to the integration branch with a rule that could refuse a push or a PR update. Any other output is a stop: report the ruleset's id and name
and tell the owner to delete it (Settings, Rules). A ruleset for `main` or another pattern does not match and is not a stop.
