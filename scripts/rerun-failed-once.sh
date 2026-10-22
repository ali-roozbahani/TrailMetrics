#!/bin/bash
# Re-runs the failed jobs of a finished GitHub Actions run, once (tm-agent-loop, section 6).
# The only way an agent re-runs a CI job: "once" is enforced here, not left to prose.
#
#   scripts/rerun-failed-once.sh <run id>
#   scripts/rerun-failed-once.sh --self-test
#
# Reads the run through REST (`gh api`, GraphQL is refused here). Prints one line.
# Exit 0 (RERUN ...) only when the run is completed, its conclusion is failure and its
# `run_attempt` is 1; it then runs `gh run rerun <id> --failed`. Anything else prints
# `REFUSED <id>: <why>` and exits 1, and re-runs nothing: a run_attempt of 2 or more, a run
# that is not completed, a conclusion other than failure, unreadable data, a failed `gh` call.
# Exit 2 is a usage error or a missing tool.
#
# --self-test runs every case in scripts/rerun-failed-once-fixtures/ against a fake `gh` (no
# network): a case directory holds run.json (or an empty gh-fail file for a `gh` that fails),
# the expected output line, the expected exit code and whether a re-run is expected (yes|no).
# Bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/scripts/rerun-failed-once-fixtures"

refuse() {
    echo "REFUSED $ID: $1"
    exit 1
}

rerun() {
    local status conclusion attempt
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' EXIT

    gh api "repos/{owner}/{repo}/actions/runs/$ID" > "$d/run.json" 2>/dev/null || refuse "gh api failed"
    attempt="$(jq -r '.run_attempt // empty' "$d/run.json" 2>/dev/null)" || refuse "run data is not readable"
    status="$(jq -r '.status // empty' "$d/run.json" 2>/dev/null)" || refuse "run data is not readable"
    conclusion="$(jq -r '.conclusion // empty' "$d/run.json" 2>/dev/null)" || refuse "run data is not readable"

    case "$attempt" in
        '' | *[!0-9]*) refuse "run_attempt is not a number" ;;
    esac
    [ "$attempt" -lt 2 ] || refuse "run_attempt is $attempt, a run is re-run once"
    [ "$status" = completed ] || refuse "run is ${status:-unknown}, not completed"
    [ "$conclusion" = failure ] || refuse "conclusion is ${conclusion:-none}, not failure"

    gh run rerun "$ID" --failed > /dev/null 2>&1 || refuse "gh run rerun failed"
    echo "RERUN $ID: attempt $attempt failed, re-running the failed jobs"
}

self_test() {
    local failed=0 dir name log expected expected_exit expected_rerun actual code reran
    log="$(mktemp)"
    for dir in "$FIXTURES"/*/; do
        name="$(basename "$dir")"
        expected="$(cat "$dir/expected")"
        expected_exit="$(cat "$dir/expected-exit")"
        expected_rerun="$(cat "$dir/expected-rerun")"
        : > "$log"
        actual="$(PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$dir" FAKE_GH_LOG="$log" "$0" 555)"
        code=$?
        if [ -s "$log" ]; then reran=yes; else reran=no; fi
        if [ "$actual" = "$expected" ] && [ "$code" = "$expected_exit" ] && [ "$reran" = "$expected_rerun" ]; then
            echo "ok   $name: $actual (exit $code, re-run $reran)"
        else
            echo "FAIL $name: expected '$expected' exit $expected_exit re-run $expected_rerun, got '$actual' exit $code re-run $reran"
            failed=1
        fi
    done
    rm -f "$log"
    # usage errors exit 2
    "$0" > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL no argument does not exit 2"; failed=1; }
    "$0" abc > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL a non-numeric run id does not exit 2"; failed=1; }
    if [ "$failed" = 0 ]; then echo "rerun-failed-once: self-test passed"; else echo "rerun-failed-once: self-test FAILED"; fi
    exit "$failed"
}

if [ "${1:-}" = "--self-test" ] && [ "$#" = 1 ]; then
    self_test
fi
if [ "$#" != 1 ] || ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "usage: scripts/rerun-failed-once.sh <run id> | --self-test" >&2
    exit 2
fi
for tool in gh jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is not installed" >&2; exit 2; }
done
ID="$1"
rerun
