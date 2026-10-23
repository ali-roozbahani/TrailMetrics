#!/bin/bash
# Waits until every check run of a commit is completed (tm-agent-loop, section 6).
# The wait is a command, so an agent runs it in the background and is re-invoked when it exits:
# a foreground `sleep` is blocked or capped in the agent's shell.
#
#   scripts/wait-for-checks.sh <PR number | head SHA (40 hex)>
#   scripts/wait-for-checks.sh --self-test
#
# Given a PR number it resolves the head SHA, and reads the PR again on every step: a newer push
# changes the head. Given a SHA there is no PR to compare with, so SUPERSEDED cannot happen.
# Reads only through REST (`gh api` GET, GraphQL is refused here):
#   repos/{owner}/{repo}/pulls/<N>
#   repos/{owner}/{repo}/commits/<sha>/check-runs?filter=latest&per_page=100   (first page only)
# It never cancels or re-runs anything.
#
# Steps: every 30 s for the first 5 minutes, then every 5 minutes, at most 90 minutes in all.
# A SHA with no check run yet (CI not started) is not finished; it waits until the timeout.
#
# Output on exit: one tab-separated line per check run (name, status, conclusion; `-` when none),
# then one summary line, and the exit code:
#   ALL_GREEN                       every run completed, all success or skipped          exit 0
#   FAILED <names>                  every run completed, others had another conclusion   exit 1
#   TIMEOUT <names still running>   the maximum wait ran out                             exit 1
#   SUPERSEDED <new sha>            the PR head is no longer the SHA being watched       exit 1
# Names are joined with "; ". Exit 2 is a usage error, a missing tool, or a failed `gh` call.
#
# Environment (whole seconds), to shorten the wait for the self-test:
#   WAIT_FOR_CHECKS_MAX_SECONDS (5400)  WAIT_FOR_CHECKS_FAST_SECONDS (300, length of the fast phase)
#   WAIT_FOR_CHECKS_FAST_STEP (30)      WAIT_FOR_CHECKS_SLOW_STEP (300)
#
# --self-test runs every case in scripts/wait-for-checks-fixtures/ against a fake `gh` (no network):
# a case directory holds `arg` (the argument), check-runs-N.json (the N-th read of the check runs;
# the last file repeats), pr-N.json (the N-th read of the PR, for a PR number), `expected` (the
# output), `expected-exit`, or `gh-fail` for a `gh` that always fails. Bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/scripts/wait-for-checks-fixtures"
USAGE="usage: scripts/wait-for-checks.sh <PR number | head SHA> | --self-test"

die() {
    echo "wait-for-checks: $1" >&2
    exit 2
}

wait_for_checks() {
    local elapsed=0 step remaining new_sha total pending names d
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' EXIT

    while :; do
        if [ -n "$PR" ]; then
            gh api "repos/{owner}/{repo}/pulls/$PR" > "$d/pr.json" 2>/dev/null || die "gh api failed reading PR $PR"
            new_sha="$(jq -r '.head.sha // empty' "$d/pr.json" 2>/dev/null)" || die "PR data is not readable"
            [ -n "$new_sha" ] || die "PR $PR has no head sha"
            if [ -z "$SHA" ]; then
                SHA="$new_sha"
            elif [ "$new_sha" != "$SHA" ]; then
                echo "SUPERSEDED $new_sha"
                exit 1
            fi
        fi

        gh api "repos/{owner}/{repo}/commits/$SHA/check-runs?filter=latest&per_page=100" > "$d/runs.json" 2>/dev/null \
            || die "gh api failed reading the check runs of $SHA"
        jq -e '.check_runs | type == "array"' "$d/runs.json" > /dev/null 2>&1 || die "check run data is not readable"
        total="$(jq -r '.check_runs | length' "$d/runs.json")"
        pending="$(jq -r '[.check_runs[] | select(.status != "completed")] | length' "$d/runs.json")"

        if [ "$total" -gt 0 ] && [ "$pending" = 0 ]; then
            print_rows "$d/runs.json"
            names="$(jq -r '[.check_runs[] | select(.conclusion as $c | ["success", "skipped"] | index($c) | not) | .name] | join("; ")' "$d/runs.json")"
            if [ -z "$names" ]; then
                echo "ALL_GREEN"
                exit 0
            fi
            echo "FAILED $names"
            exit 1
        fi

        if [ "$elapsed" -ge "$MAX" ]; then
            print_rows "$d/runs.json"
            names="$(jq -r '[.check_runs[] | select(.status != "completed") | .name] | join("; ")' "$d/runs.json")"
            echo "TIMEOUT ${names:-(no check runs yet)}"
            exit 1
        fi

        if [ "$elapsed" -lt "$FAST_PHASE" ]; then step="$FAST_STEP"; else step="$SLOW_STEP"; fi
        remaining=$((MAX - elapsed))
        [ "$step" -le "$remaining" ] || step="$remaining"
        sleep "$step"
        elapsed=$((elapsed + step))
    done
}

print_rows() {
    jq -r '.check_runs[] | [.name, .status, (.conclusion // "-")] | @tsv' "$1"
}

self_test() {
    local failed=0 dir name expected expected_exit actual code state
    for dir in "$FIXTURES"/*/; do
        name="$(basename "$dir")"
        expected="$(cat "$dir/expected")"
        expected_exit="$(cat "$dir/expected-exit")"
        state="$(mktemp -d)"
        actual="$(PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$dir" FAKE_GH_STATE="$state" \
            WAIT_FOR_CHECKS_MAX_SECONDS=3 WAIT_FOR_CHECKS_FAST_SECONDS=2 \
            WAIT_FOR_CHECKS_FAST_STEP=1 WAIT_FOR_CHECKS_SLOW_STEP=1 "$0" "$(cat "$dir/arg")" 2>/dev/null)"
        code=$?
        rm -rf "$state"
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
    "$0" > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL no argument does not exit 2"; failed=1; }
    "$0" abc > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL a non-numeric, non-SHA argument does not exit 2"; failed=1; }
    "$0" 12 13 > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL two arguments do not exit 2"; failed=1; }
    WAIT_FOR_CHECKS_MAX_SECONDS=x "$0" 12 > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL a non-numeric time does not exit 2"; failed=1; }
    if [ "$failed" = 0 ]; then echo "wait-for-checks: self-test passed"; else echo "wait-for-checks: self-test FAILED"; fi
    exit "$failed"
}

if [ "${1:-}" = "--self-test" ] && [ "$#" = 1 ]; then
    self_test
fi

MAX="${WAIT_FOR_CHECKS_MAX_SECONDS:-5400}"
FAST_PHASE="${WAIT_FOR_CHECKS_FAST_SECONDS:-300}"
FAST_STEP="${WAIT_FOR_CHECKS_FAST_STEP:-30}"
SLOW_STEP="${WAIT_FOR_CHECKS_SLOW_STEP:-300}"
for v in "$MAX" "$FAST_PHASE" "$FAST_STEP" "$SLOW_STEP"; do
    case "$v" in
        '' | *[!0-9]*) echo "$USAGE" >&2; echo "the WAIT_FOR_CHECKS_* times are whole seconds" >&2; exit 2 ;;
    esac
done
if [ "$FAST_STEP" = 0 ] || [ "$SLOW_STEP" = 0 ]; then
    echo "the WAIT_FOR_CHECKS_*_STEP times must be at least 1 second" >&2
    exit 2
fi

PR=""
SHA=""
if [ "$#" != 1 ]; then
    echo "$USAGE" >&2
    exit 2
fi
if [[ "$1" =~ ^[0-9a-f]{40}$ ]]; then
    SHA="$1"
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    PR="$1"
else
    echo "$USAGE" >&2
    exit 2
fi
for tool in gh jq; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
wait_for_checks
