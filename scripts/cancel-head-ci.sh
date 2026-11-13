#!/bin/bash
# Cancels the workflow runs of an open pull request's current head that have not finished, at the moment
# the agent decides to fix a reviewer finding (tm-agent-loop, section 6): the fix replaces that head, and
# the old head's CI would otherwise keep a runner busy until the push cancels it (ci.yml and
# pr-review.yml use `cancel-in-progress`). The one place where the loop cancels a run; it never cancels
# anything else, and `scripts/rerun-failed-once.sh` and `scripts/wait-for-checks.sh` never do.
#
#   scripts/cancel-head-ci.sh <PR number>
#   scripts/cancel-head-ci.sh --self-test
#
# Reads the PR (`gh api repos/{owner}/{repo}/pulls/<N>`) and refuses, exit 1, unless it is open, from a
# branch of this repository, and authored by the account `gh` is logged in as. Then lists the runs of
# the PR's head SHA (`actions/runs?head_sha=<sha>`), keeps those with event `pull_request` and that same
# head SHA whose status is not `completed`, and cancels each with `POST actions/runs/<id>/cancel`.
# Output: one line `CANCELLED <run id> <workflow name>` per run, then
# `CANCEL_DONE <n> cancelled, <m> already finished` (exit 0). A run that finished meanwhile is a refusal
# of GitHub's cancel call: it is counted as finished, not as an error. Exit 1: refused (reason on
# stderr). Exit 2: usage error, a missing tool or a `gh` read that failed. Cancelling takes a few
# seconds to show; the runs of the superseded head then end as `cancelled`, which is expected
# (tm-agent-loop, section 6, "SUPERSEDED").
#
# --self-test runs every case in scripts/cancel-head-ci-fixtures/ against a fake `gh` (no network): a case
# directory holds `arg`, pr.json, runs.json, `login` (the account), `expected` (output), `expected-exit`,
# `expected-posts` (the cancel calls the fake recorded, one run id per line; empty when none) and optionally
# `gh-fail` (a `gh` that always fails) or `cancel-fails` (every cancel call is refused, as for a finished run).
# Bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/scripts/cancel-head-ci-fixtures"
USAGE="usage: scripts/cancel-head-ci.sh <PR number> | --self-test"

cancel_runs() {
    local pr="$1" d me json sha state author head_repo base_repo n=0 done_n=0 id name rows status
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' EXIT
    gh api "repos/{owner}/{repo}/pulls/$pr" > "$d/pr.json" 2>/dev/null || { echo "cancel-head-ci: reading PR $pr failed" >&2; exit 2; }
    me="$(gh api user --jq .login 2>/dev/null)" || { echo "cancel-head-ci: reading the gh login failed" >&2; exit 2; }
    state="$(jq -r '.state // empty' "$d/pr.json" 2>/dev/null)" || { echo "cancel-head-ci: PR data is not readable" >&2; exit 2; }
    sha="$(jq -r '.head.sha // empty' "$d/pr.json")"
    author="$(jq -r '.user.login // empty' "$d/pr.json")"
    head_repo="$(jq -r '.head.repo.full_name // empty' "$d/pr.json")"
    base_repo="$(jq -r '.base.repo.full_name // empty' "$d/pr.json")"
    [ -n "$sha" ] && [ -n "$me" ] || { echo "cancel-head-ci: PR data is incomplete" >&2; exit 2; }
    [ "$state" = open ] || { echo "cancel-head-ci: refused: PR $pr is $state, not open" >&2; exit 1; }
    [ "$author" = "$me" ] || { echo "cancel-head-ci: refused: PR $pr is by $author, not by $me" >&2; exit 1; }
    [ -n "$head_repo" ] && [ "$head_repo" = "$base_repo" ] || { echo "cancel-head-ci: refused: PR $pr is not from a branch of this repository" >&2; exit 1; }

    gh api "repos/{owner}/{repo}/actions/runs?head_sha=$sha&per_page=100" > "$d/runs.json" 2>/dev/null || { echo "cancel-head-ci: reading the runs of $sha failed" >&2; exit 2; }
    rows="$(jq -r --arg sha "$sha" '.workflow_runs[] | select(.head_sha == $sha and .event == "pull_request" and .status != "completed") | "\(.id)\t\(.name)"' "$d/runs.json" 2>/dev/null)" \
        || { echo "cancel-head-ci: run data is not readable" >&2; exit 2; }
    done_n="$(jq -r --arg sha "$sha" '[.workflow_runs[] | select(.head_sha == $sha and .event == "pull_request" and .status == "completed")] | length' "$d/runs.json")"
    while IFS="$(printf '\t')" read -r id name; do
        [ -n "$id" ] || continue
        if gh api -X POST "repos/{owner}/{repo}/actions/runs/$id/cancel" > /dev/null 2>&1; then
            echo "CANCELLED $id $name"
            n=$((n + 1))
        else
            done_n=$((done_n + 1))
        fi
    done <<< "$rows"
    echo "CANCEL_DONE $n cancelled, $done_n already finished"
}

self_test() {
    local failed=0 dir name expected expected_exit actual code state posts want_posts
    for dir in "$FIXTURES"/*/; do
        name="$(basename "$dir")"
        expected="$(cat "$dir/expected")"
        expected_exit="$(cat "$dir/expected-exit")"
        want_posts="$(cat "$dir/expected-posts" 2>/dev/null)"
        state="$(mktemp -d)"
        actual="$(PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$dir" FAKE_GH_STATE="$state" "$0" $(cat "$dir/arg") 2>/dev/null)"
        code=$?
        posts="$(cat "$state/posts" 2>/dev/null)"
        rm -rf "$state"
        if [ "$actual" = "$expected" ] && [ "$code" = "$expected_exit" ] && [ "$posts" = "$want_posts" ]; then
            echo "ok   $name (exit $code)"
        else
            echo "FAIL $name: expected exit $expected_exit, output and cancel calls"
            echo "$expected" | sed 's/^/       /'; echo "       posts: [$want_posts]"
            echo "     got exit $code, output and cancel calls"
            echo "$actual" | sed 's/^/       /'; echo "       posts: [$posts]"
            failed=1
        fi
    done
    "$0" > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL no argument does not exit 2"; failed=1; }
    "$0" abc > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL a non-numeric argument does not exit 2"; failed=1; }
    "$0" 1 2 > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL two arguments do not exit 2"; failed=1; }
    if [ "$failed" = 0 ]; then echo "cancel-head-ci: self-test passed"; else echo "cancel-head-ci: self-test FAILED"; fi
    exit "$failed"
}

if [ "${1:-}" = "--self-test" ] && [ "$#" = 1 ]; then
    self_test
fi
[ "$#" = 1 ] && [[ "$1" =~ ^[0-9]+$ ]] || { echo "$USAGE" >&2; exit 2; }
for tool in gh jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "cancel-head-ci: $tool is not installed" >&2; exit 2; }
done
cancel_runs "$1"
