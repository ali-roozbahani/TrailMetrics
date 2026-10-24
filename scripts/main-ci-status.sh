#!/bin/bash
# Prints the result of the CI run that a `push` to `main` started (tm-pr-workflow, "Before starting";
# tm-agent-loop, "After-merge cleanup"). Nobody else reads that run: a PR is green before the merge,
# and `main` can still be red after it.
#
#   scripts/main-ci-status.sh                 the latest completed `push` run of ci.yml on main
#   scripts/main-ci-status.sh --sha <sha>     the push run of that one commit (40 hex)
#   scripts/main-ci-status.sh --self-test
#
# Reads only through REST (`gh api` GET, GraphQL is refused here); `origin/main`'s head is read
# from the local ref, so run `git fetch origin` first. It never cancels or re-runs anything.
#
# Output: a line `run <id> <sha> <conclusion> <url>`, a line `failed jobs: <names>` for a red run,
# a line `of head` (the run is the one of origin/main's head) or `OLDER than head <sha>` (head has
# no completed run: not started yet or still running; the result shown is the latest completed
# one), then one summary line and the exit code:
#   MAIN_GREEN <sha>                       the run of the commit concluded success             exit 0
#   MAIN_RED <sha> <failed jobs>           failure, timed_out or startup_failure               exit 1
#   MAIN_RUNNING <sha>                     the commit's run is queued or in progress, or no
#                                          run exists yet (a push run appears a few seconds
#                                          after the merge); an older result is printed above  exit 3
#   MAIN_UNKNOWN <reason>                  a failed `gh` call, unreadable data, a conclusion
#                                          that is neither green nor red (cancelled, ...)      exit 4
# Without --sha the commit is origin/main's head. A usage error exits 2.
# Environment: MAIN_CI_STATUS_HEAD (a 40-hex SHA) replaces the local ref, for the self-test.
#
# --self-test runs every case in scripts/main-ci-status-fixtures/ against a fake `gh` (no network):
# a case directory holds `arg` (the arguments), `head` (origin/main's head), runs.json (the run list),
# jobs-<run id>.json (the jobs of a run), `expected` (the output), `expected-exit`, and `gh-fail` for
# a `gh` that always fails or `gh-fail-jobs` for a `gh` that fails only on the jobs read.
# Bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/scripts/main-ci-status-fixtures"
USAGE="usage: scripts/main-ci-status.sh [--sha <sha>] | --self-test"

unknown() {
    echo "MAIN_UNKNOWN $1"
    exit 4
}

self_test() {
    local failed=0 dir name expected expected_exit actual code
    for dir in "$FIXTURES"/*/; do
        name="$(basename "$dir")"
        expected="$(cat "$dir/expected")"
        expected_exit="$(cat "$dir/expected-exit")"
        actual="$(PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$dir" MAIN_CI_STATUS_HEAD="$(cat "$dir/head")" \
            "$0" $(cat "$dir/arg") 2>/dev/null)"
        code=$?
        if [ "$actual" = "$expected" ] && [ "$code" = "$expected_exit" ]; then
            echo "ok   $name (exit $code)"
        else
            echo "FAIL $name: expected exit $expected_exit and"
            echo "$expected" | sed 's/^/       /'
            echo "     got exit $code and"
            echo "$actual" | sed 's/^/       /'
            failed=1
        fi
    done
    # usage errors exit 2
    "$0" abc > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL an unknown argument does not exit 2"; failed=1; }
    "$0" --sha > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --sha without a value does not exit 2"; failed=1; }
    "$0" --sha xyz > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --sha with a non-SHA does not exit 2"; failed=1; }
    "$0" --sha aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa extra > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL an extra argument does not exit 2"; failed=1; }
    if [ "$failed" = 0 ]; then echo "main-ci-status: self-test passed"; else echo "main-ci-status: self-test FAILED"; fi
    exit "$failed"
}

if [ "${1:-}" = "--self-test" ] && [ "$#" = 1 ]; then
    self_test
fi

SHA=""
if [ "$#" = 0 ]; then
    :
elif [ "$#" = 2 ] && [ "$1" = "--sha" ] && [[ "$2" =~ ^[0-9a-f]{40}$ ]]; then
    SHA="$2"
else
    echo "$USAGE" >&2
    exit 2
fi
for tool in gh jq git; do
    command -v "$tool" >/dev/null 2>&1 || unknown "$tool is not installed"
done

HEAD_SHA="${MAIN_CI_STATUS_HEAD:-$(git rev-parse --verify -q origin/main 2>/dev/null)}"
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || unknown "origin/main is not readable"
WANT="${SHA:-$HEAD_SHA}"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
gh api "repos/{owner}/{repo}/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=100" > "$D/runs.json" 2>/dev/null \
    || unknown "gh api failed reading the runs of ci.yml"
jq -e '.workflow_runs | type == "array"' "$D/runs.json" > /dev/null 2>&1 || unknown "the run list is not readable"

# The newest run of the wanted commit (the list is newest first) and the newest completed run.
RUN="$(jq -c --arg sha "$WANT" '[.workflow_runs[] | select(.head_sha == $sha)] | .[0] // empty' "$D/runs.json")"
if [ -z "$RUN" ] || [ "$(jq -r '.status' <<< "$RUN")" != "completed" ]; then
    if [ -z "$SHA" ]; then
        OLD="$(jq -c '[.workflow_runs[] | select(.status == "completed")] | .[0] // empty' "$D/runs.json")"
        if [ -n "$OLD" ]; then
            echo "latest completed: run $(jq -r '.id' <<< "$OLD") $(jq -r '.head_sha' <<< "$OLD") $(jq -r '.conclusion' <<< "$OLD") (OLDER than head $WANT)"
        fi
    fi
    echo "MAIN_RUNNING $WANT"
    exit 3
fi

ID="$(jq -r '.id' <<< "$RUN")"
CONCLUSION="$(jq -r '.conclusion // "-"' <<< "$RUN")"
echo "run $ID $WANT $CONCLUSION $(jq -r '.html_url' <<< "$RUN")"
if [ "$WANT" = "$HEAD_SHA" ]; then echo "of head"; else echo "OLDER than head $HEAD_SHA"; fi

case "$CONCLUSION" in
    success)
        echo "MAIN_GREEN $WANT"
        exit 0
        ;;
    failure | timed_out | startup_failure)
        gh api "repos/{owner}/{repo}/actions/runs/$ID/jobs?per_page=100" > "$D/jobs.json" 2>/dev/null \
            || unknown "gh api failed reading the jobs of run $ID"
        jq -e '.jobs | type == "array"' "$D/jobs.json" > /dev/null 2>&1 || unknown "the job list of run $ID is not readable"
        NAMES="$(jq -r '[.jobs[] | select(.conclusion as $c | ["success", "skipped"] | index($c) | not) | .name] | join("; ")' "$D/jobs.json")"
        echo "failed jobs: ${NAMES:-(none listed)}"
        echo "MAIN_RED $WANT ${NAMES:-(none listed)}"
        exit 1
        ;;
    *)
        unknown "run $ID concluded '$CONCLUSION'"
        ;;
esac
