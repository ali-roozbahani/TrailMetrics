#!/bin/bash
# Waits until every check run of a commit is completed (tm-agent-loop, section 6).
# The wait is a command, so an agent runs it in the background and is re-invoked when it exits:
# a foreground `sleep` is blocked or capped in the agent's shell.
#
#   scripts/wait-for-checks.sh [--ci-only] <PR number | head SHA (40 hex)>
#   scripts/wait-for-checks.sh --self-test
#
# --ci-only is for a merge commit on `main`: a `push` to `main` never starts `Review — pr-reviewer`
# (pr-review.yml runs on pull requests), so that check is not waited for. The three CI checks must
# exist; any check run that does exist is still read, and a failed one is FAILED. Without the
# option the list is unchanged. It takes a SHA (a PR number would be a PR head, which has the review).
#
# Given a PR number it resolves the head SHA, and reads the PR again on every step: a newer push
# changes the head. Given a SHA there is no PR to compare with, so SUPERSEDED cannot happen.
# Reads only through REST (`gh api` GET, GraphQL is refused here):
#   repos/{owner}/{repo}/pulls/<N>
#   repos/{owner}/{repo}/commits/<sha>/check-runs?filter=latest&per_page=100   (first page only)
# It never cancels or re-runs anything.
#
# Steps: every 30 s for the first 5 minutes, then every 5 minutes, at most 90 minutes in all.
# The check runs of a push appear one after another (jobs of ci.yml, `Review — pr-reviewer` of
# another workflow, a job that needs another one), so "every run I see is completed" is not enough:
# the run is finished only when every check run in REQUIRED_CHECKS (below) exists and all runs are
# completed. A SHA with no check run yet (CI not started) is not finished; it waits until the timeout.
# A failed `gh` call is retried: up to 3 failed reads in a row (one step of sleep between them, the
# count resets on a success); the 4th in a row exits 2.
#
# Output on exit: one tab-separated line per check run (name, status, conclusion; `-` when none),
# then one summary line, and the exit code:
#   ALL_GREEN                       every run completed, all success or skipped          exit 0
#   FAILED <names>                  every run completed, others had another conclusion   exit 1
#   FAILED Review — pr-reviewer[; still running: <names>][; missing: <names>]
#                                   the reviewer's check run is completed with a conclusion
#                                   other than success or skipped (`failure` for CHANGES and for
#                                   a run with no verdict) while other runs are still running
#                                   or not started: the wait ends early, those runs are listed
#                                   (running ones show their status and `-` in their row).
#                                   Required runs that do not exist yet are named after
#                                   "missing:". When nothing is left to wait for, the plain FAILED line
#                                   above is printed instead                             exit 1
#   TIMEOUT <names still running>[; missing: <names>]
#                                   the maximum wait ran out; "(none running)" when only
#                                   required runs are missing                            exit 1
#   SUPERSEDED <new sha>            the PR head is no longer the SHA being watched       exit 1
# The early exit is only for the reviewer: it finishes in about 2 minutes, the Android and iOS jobs
# in 15 to 40, and its verdict is read with scripts/read-ci-verdict.sh. Any other failed check
# keeps the wait until every run is completed (scripts/rerun-failed-once.sh refuses a run that is
# not completed). A reviewer still running, with another check failed, is waited for.
# Names are joined with "; ". Exit 2 is a usage error, a missing tool, unreadable data, or a `gh`
# call that failed 4 times in a row.
#
# Environment (whole seconds), to shorten the wait for the self-test:
#   WAIT_FOR_CHECKS_MAX_SECONDS (5400)  WAIT_FOR_CHECKS_FAST_SECONDS (300, length of the fast phase)
#   WAIT_FOR_CHECKS_FAST_STEP (30)      WAIT_FOR_CHECKS_SLOW_STEP (300)
#
# --self-test runs every case in scripts/wait-for-checks-fixtures/ against a fake `gh` (no network):
# a case directory holds `arg` (the argument), check-runs-N.json (the N-th read of the check runs;
# the last file repeats), pr-N.json (the N-th read of the PR, for a PR number), `expected` (the
# output), `expected-exit`, optionally `expected-stderr` (text the error output must contain), and
# `gh-fail` for a `gh` that always fails or `gh-fail-calls` (numbers of the `gh` calls that fail).
# Bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/scripts/wait-for-checks-fixtures"
# The check runs that must exist, by exact name, for ALL_GREEN: the three required checks of
# tm-agent-loop section 8 (branch protection) and the CI reviewer's check run
# (.github/workflows/pr-review.yml). One name per line (names contain commas). If a check is
# renamed, the run waits until the timeout and names it as missing instead of turning green:
# update this list with the rename.
REQUIRED_CHECKS="Android — Lint, Detekt, Tests, Build
iOS — all stages
Repo tooling — policy checks and script self-tests
Review — pr-reviewer"
REVIEWER_CHECK="Review — pr-reviewer"
USAGE="usage: scripts/wait-for-checks.sh [--ci-only] <PR number | head SHA> | --self-test"

die() {
    echo "wait-for-checks: $1" >&2
    exit 2
}

elapsed=0
fails=0

# The sleep before the next read: 30 s in the fast phase, 5 minutes after, never past the maximum.
next_step() {
    local remaining
    if [ "$elapsed" -lt "$FAST_PHASE" ]; then STEP="$FAST_STEP"; else STEP="$SLOW_STEP"; fi
    remaining=$((MAX - elapsed))
    [ "$remaining" -ge 0 ] || remaining=0
    [ "$STEP" -le "$remaining" ] || STEP="$remaining"
}

# fetch <output file> <endpoint> <what>: one `gh api` read. A failed call is retried after one step
# of sleep, up to 3 failures in a row; the 4th exits 2. A success resets the count.
fetch() {
    until gh api "$2" > "$1" 2>/dev/null; do
        fails=$((fails + 1))
        [ "$fails" -le 3 ] || die "gh api failed $fails times in a row reading $3"
        next_step
        sleep "$STEP"
        elapsed=$((elapsed + STEP))
    done
    fails=0
}

wait_for_checks() {
    local new_sha total pending names missing d
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' EXIT

    while :; do
        if [ -n "$PR" ]; then
            fetch "$d/pr.json" "repos/{owner}/{repo}/pulls/$PR" "PR $PR"
            new_sha="$(jq -r '.head.sha // empty' "$d/pr.json" 2>/dev/null)" || die "PR data is not readable"
            [ -n "$new_sha" ] || die "PR $PR has no head sha"
            if [ -z "$SHA" ]; then
                SHA="$new_sha"
            elif [ "$new_sha" != "$SHA" ]; then
                echo "SUPERSEDED $new_sha"
                exit 1
            fi
        fi

        fetch "$d/runs.json" "repos/{owner}/{repo}/commits/$SHA/check-runs?filter=latest&per_page=100" "the check runs of $SHA"
        jq -e '.check_runs | type == "array"' "$d/runs.json" > /dev/null 2>&1 || die "check run data is not readable"
        total="$(jq -r '.check_runs | length' "$d/runs.json")"
        pending="$(jq -r '[.check_runs[] | select(.status != "completed")] | length' "$d/runs.json")"
        missing="$(jq -r --arg required "$REQUIRED_CHECKS" '[.check_runs[].name] as $have
            | [$required | split("\n")[] | select(. != "") | select(. as $n | ($have | index($n)) == null)] | join("; ")' "$d/runs.json")"

        if [ "$total" -gt 0 ] && [ "$pending" = 0 ] && [ -z "$missing" ]; then
            print_rows "$d/runs.json"
            names="$(jq -r '[.check_runs[] | select(.conclusion as $c | ["success", "skipped"] | index($c) | not) | .name] | join("; ")' "$d/runs.json")"
            if [ -z "$names" ]; then
                echo "ALL_GREEN"
                exit 0
            fi
            echo "FAILED $names"
            exit 1
        fi

        reviewer_failed="$(jq -r --arg name "$REVIEWER_CHECK" '[.check_runs[] | select(.name == $name and .status == "completed"
            and (.conclusion as $c | ["success", "skipped"] | index($c) | not))] | length' "$d/runs.json")"
        if [ "$reviewer_failed" != 0 ]; then
            print_rows "$d/runs.json"
            names="$(jq -r '[.check_runs[] | select(.status != "completed") | .name] | join("; ")' "$d/runs.json")"
            echo "FAILED $REVIEWER_CHECK${names:+; still running: $names}${missing:+; missing: $missing}"
            exit 1
        fi

        if [ "$elapsed" -ge "$MAX" ]; then
            print_rows "$d/runs.json"
            names="$(jq -r '[.check_runs[] | select(.status != "completed") | .name] | join("; ")' "$d/runs.json")"
            echo "TIMEOUT ${names:-(none running)}${missing:+; missing: $missing}"
            exit 1
        fi

        next_step
        sleep "$STEP"
        elapsed=$((elapsed + STEP))
    done
}

print_rows() {
    jq -r '.check_runs[] | [.name, .status, (.conclusion // "-")] | @tsv' "$1"
}

self_test() {
    local failed=0 dir name expected expected_exit actual code state err
    for dir in "$FIXTURES"/*/; do
        name="$(basename "$dir")"
        expected="$(cat "$dir/expected")"
        expected_exit="$(cat "$dir/expected-exit")"
        state="$(mktemp -d)"
        err="$state/stderr"
        actual="$(PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$dir" FAKE_GH_STATE="$state" \
            WAIT_FOR_CHECKS_MAX_SECONDS=3 WAIT_FOR_CHECKS_FAST_SECONDS=2 \
            WAIT_FOR_CHECKS_FAST_STEP=1 WAIT_FOR_CHECKS_SLOW_STEP=1 "$0" $(cat "$dir/arg") 2>"$err")"
        code=$?
        if [ -e "$dir/expected-stderr" ] && ! grep -qF -- "$(cat "$dir/expected-stderr")" "$err"; then
            code="$code (stderr lacks '$(cat "$dir/expected-stderr")')"
        fi
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
    "$0" --ci-only 12 > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --ci-only with a PR number does not exit 2"; failed=1; }
    "$0" --ci-only > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --ci-only without a SHA does not exit 2"; failed=1; }
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
if [ "${1:-}" = "--ci-only" ]; then
    # Drop the reviewer's check run from the list that must exist (the last line of REQUIRED_CHECKS).
    REQUIRED_CHECKS="$(printf '%s\n' "$REQUIRED_CHECKS" | grep -vxF 'Review — pr-reviewer')"
    CI_ONLY=1
    shift
fi
if [ "$#" != 1 ]; then
    echo "$USAGE" >&2
    exit 2
fi
if [[ "$1" =~ ^[0-9a-f]{40}$ ]]; then
    SHA="$1"
elif [[ "$1" =~ ^[0-9]+$ ]] && [ -z "${CI_ONLY:-}" ]; then
    PR="$1"
else
    echo "$USAGE" >&2
    exit 2
fi
for tool in gh jq; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
wait_for_checks
