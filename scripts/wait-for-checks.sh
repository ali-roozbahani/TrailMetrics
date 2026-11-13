#!/bin/bash
# Waits until every check run of a commit is completed, or until the reviewer's check has failed
# (tm-agent-loop, section 6); with --review-first until the reviewer's check is completed.
# The wait is a command, so an agent runs it in the background and is re-invoked when it exits:
# a foreground `sleep` is blocked or capped in the agent's shell.
#
#   scripts/wait-for-checks.sh [--review-first | --until-complete] [--review-acked] [--max-seconds <n>] <PR number | head SHA (40 hex)>
#   scripts/wait-for-checks.sh --self-test
#
# The reviewer's verdict is acted on the moment it is posted, never after the rest of CI (tm-agent-loop,
# section 6). Given a PR number, the wait reads the verdict itself (scripts/read-ci-verdict.sh, retried
# while it says UNKNOWN: the annotation can lag the check run by a moment) as soon as the check run
# `Review — pr-reviewer` is completed with success or skipped, in the default mode and with
# --review-first, and prints `REVIEW_VERDICT <the verdict line>`. A bare `APPROVE` needs nothing: the
# wait goes on. Anything else needs the agent now: `ESCALATE_TO_HUMAN` (its report may hold a
# `[blocking]` finding the line does not show), `CHANGES`, `UNKNOWN <reason>`, or `APPROVE, <n>
# important` with n above 0. The wait then ends at once, with the other jobs still running, like a
# failed job does:
#   REVIEW_ACTION <verdict line>; still running: <names|(none)>[; missing: <names>]      exit 4
# The agent reads the report (tm-agent-loop, section 7), fixes or disposes each finding, and, when it is
# not pushing a fix, runs the same command again with --review-acked, which prints the verdict once more
# and then waits for the rest as before. A head given as a SHA has no PR to read the verdict for, and
# --until-complete (the wait after a flake) does not read it: both behave as before.
#
# --review-first waits only for the check run `Review — pr-reviewer` of the SHA to be completed
# (about 2 minutes) and never for the other jobs: the agent fixes what the verdict shows while Android
# and iOS still run (tm-agent-loop, section 6). It prints the rows, `REVIEW_VERDICT <line>` (given a PR
# number) and `REVIEW_DONE <conclusion>; still running: <names>[; missing: <names>]` (exit 0) for a
# conclusion of success or skipped and a verdict that needs nothing; "(none)" when nothing is running.
# A verdict that needs action is `REVIEW_ACTION` (exit 4) as above. Any other conclusion is the same case as the
# early exit below: `FAILED Review — pr-reviewer[; still running: ...][; missing: ...]` (exit 1).
# Timeouts, retries of a failed `gh` read, SUPERSEDED and REST-only reads are those of the normal
# mode.
#
# --max-seconds <n> (n below the maximum wait) is for a call that must end within a cap, such as
# the 600 s of a foreground Bash call (use 540): when n seconds pass with the wait unfinished it
# prints the rows and `PENDING <names still running>[; missing: <names>]` (exit 3), and the
# caller runs the same command again (the 90 minutes are then the caller's to count: 10 PENDING
# in a row are a TIMEOUT). Without it the wait is one command up to 90 minutes, to run in the
# background (`run_in_background`, which has no 600 s cap; tm-agent-loop, section 6). Every other
# result, and its exit code, is the same with or without it.
#
# --until-complete is the wait for a run to finish after a failed job was classified as a flake: only
# the reviewer's failure ends it early; any other failed job waits until every run has completed
# (the earliest moment GitHub lets scripts/rerun-failed-once.sh re-run it).
#
# Given a PR number it resolves the head SHA, and reads the PR again on every step: a newer push
# changes the head. Given a SHA there is no PR to compare with, so SUPERSEDED cannot happen.
# Reads only through REST (`gh api` GET):
#   repos/{owner}/{repo}/pulls/<N>
#   repos/{owner}/{repo}/commits/<sha>/check-runs?filter=latest&per_page=100   (first page only)
# It never cancels or re-runs anything.
#
# When a name has more than one check run for the SHA (a PR closed and reopened), only the newest
# counts: latest `started_at` (a run not started yet counts as newest), then highest run id. The
# older ones, cancelled or not, are neither printed nor judged.
#
# The wait ends at the first failed check run, not when the last one finishes: `FAILED <failed names>;
# still running: <names>` (below). Re-running a failed job is not possible before its whole run has
# completed (GitHub offers "Re-run failed jobs" only for a finished run), so the agent reads the failed
# job's log at once and, for a defect in the PR, pushes the fix without waiting (a new push cancels the
# running CI of the old head: ci.yml `cancel-in-progress` for pull requests); only a flake waits for the
# run to finish before scripts/rerun-failed-once.sh (tm-agent-loop, section 6).
#
# Steps: every 30 s for the first 5 minutes, then every 5 minutes, at most 90 minutes in all.
# The check runs of a push appear one after another (jobs of ci.yml, `Review — pr-reviewer` of
# another workflow, a job that needs another one), so "every run I see is completed" is not enough:
# the run is finished only when every check run in REQUIRED_CHECKS (below) exists and all runs are
# completed (the reviewer's failure ends it early, see the output below). A SHA with no check run yet (CI not started) is not finished; it waits until the timeout.
# A failed `gh` call is retried: up to 3 failed reads in a row (one step of sleep between them, the
# count resets on a success); the 4th in a row exits 2.
#
# Output on exit: one tab-separated line per check run (name, status, conclusion; `-` when none),
# then one summary line, and the exit code:
#   ALL_GREEN                       every run completed, all success or skipped          exit 0
#   FAILED <names>[; still running: <names>][; missing: <names>]
#                                   a check run is completed with a conclusion other than success
#                                   or skipped (for `Review — pr-reviewer`: `failure` for CHANGES and
#                                   for a run with no verdict). The wait ends at once: runs still
#                                   running or not started are listed after "still running:" (their
#                                   row shows the status and `-`), required runs that do not exist yet
#                                   after "missing:". With nothing left running the line is the plain
#                                   `FAILED <names>`                                     exit 1
#   REVIEW_DONE <conclusion>; still running: <names|(none)>[; missing: <names>]
#                                   --review-first only: the reviewer's check run is completed
#                                   with success or skipped (and, for a PR, a bare APPROVE) exit 0
#   REVIEW_ACTION <verdict line>; still running: <names|(none)>[; missing: <names>]
#                                   the reviewer posted a verdict that needs action (above);
#                                   the other jobs are not waited for                    exit 4
#   TIMEOUT <names still running>[; missing: <names>]
#                                   the maximum wait ran out; "(none running)" when only
#                                   required runs are missing                            exit 1
#   PENDING <names still running>[; missing: <names>]
#                                   --max-seconds only: n seconds passed, nothing is decided;
#                                   run the same command again                           exit 3
#   SUPERSEDED <new sha>            the PR head is no longer the SHA being watched       exit 1
# The reviewer finishes in about 2 minutes, the Android and iOS jobs in 15 to 40; the reviewer's
# verdict is read with scripts/read-ci-verdict.sh, any other failed job by its log. With
# --review-first only the reviewer's failure ends the wait early.
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
# `gh-fail` for a `gh` that always fails or `gh-fail-calls` (numbers of the `gh` calls that fail), and
# optionally `verdict` (the line the verdict reader prints; default APPROVE; the self-test replaces
# scripts/read-ci-verdict.sh by scripts/wait-for-checks-fixtures/verdict-stub, which prints it, through
# WAIT_FOR_CHECKS_VERDICT_CMD together with WAIT_FOR_CHECKS_SELF_TEST; either alone is ignored).
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
USAGE="usage: scripts/wait-for-checks.sh [--review-first | --until-complete] [--review-acked] [--max-seconds <n>] <PR number | head SHA> | --self-test"

die() {
    echo "wait-for-checks: $1" >&2
    exit 2
}

elapsed=0
fails=0
VERDICT_LINE=""
VERDICT_CMD="$ROOT/scripts/read-ci-verdict.sh"
# Only the self-test may replace the verdict reader (it sets both variables): a leaked
# WAIT_FOR_CHECKS_VERDICT_CMD must not be able to hide a reviewer verdict in a real run.
if [ -n "${WAIT_FOR_CHECKS_SELF_TEST:-}" ] && [ -n "${WAIT_FOR_CHECKS_VERDICT_CMD:-}" ]; then
    VERDICT_CMD="$WAIT_FOR_CHECKS_VERDICT_CMD"
fi

# read_verdict: reads the reviewer's verdict for $PR and $SHA into VERDICT_LINE (up to 3 reads, one fast
# step apart, while it says UNKNOWN) and prints it.
read_verdict() {
    local i=0
    while :; do
        VERDICT_LINE="$("$VERDICT_CMD" "$PR" "$SHA" 2>/dev/null | head -n 1)"
        [ -n "$VERDICT_LINE" ] || VERDICT_LINE="UNKNOWN no verdict line"
        case "$VERDICT_LINE" in UNKNOWN*) ;; *) break ;; esac
        i=$((i + 1))
        [ "$i" -lt 3 ] || break
        sleep "$FAST_STEP"
    done
    echo "REVIEW_VERDICT $VERDICT_LINE${ACKED:+ (acknowledged)}"
}

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
    local new_sha total pending names missing d rconc rdone
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
        # Keep only the newest run per name and SHA: closing and reopening a PR leaves a second run
        # of a workflow for the same SHA, and the older one (often cancelled) must not decide.
        # Newest = latest started_at (a run not started yet counts as newest), then highest id.
        jq '.check_runs |= (. as $all | map(. as $r | ($r.started_at // "9999") as $s
            | select([$all[] | select(.name == $r.name and .head_sha == $r.head_sha
                and ([(.started_at // "9999"), (.id // 0)] > [$s, ($r.id // 0)]))] | length == 0)))' \
            "$d/runs.json" > "$d/newest.json" || die "check run data is not readable"
        mv -- "$d/newest.json" "$d/runs.json"
        total="$(jq -r '.check_runs | length' "$d/runs.json")"
        pending="$(jq -r '[.check_runs[] | select(.status != "completed")] | length' "$d/runs.json")"
        missing="$(jq -r --arg required "$REQUIRED_CHECKS" '[.check_runs[].name] as $have
            | [$required | split("\n")[] | select(. != "") | select(. as $n | ($have | index($n)) == null)] | join("; ")' "$d/runs.json")"

        # The reviewer's verdict is read the moment its check run is completed (see the header).
        if [ -z "$VERDICT_LINE" ] && [ -n "$PR" ] && [ -z "${UNTIL_COMPLETE:-}" ]; then
            rdone="$(jq -r --arg name "$REVIEWER_CHECK" '[.check_runs[] | select(.name == $name and .status == "completed"
                and (.conclusion as $c | ["success", "skipped"] | index($c)))] | length' "$d/runs.json")"
            if [ "$rdone" -gt 0 ]; then
                read_verdict
                if [ "$VERDICT_LINE" != APPROVE ] && [ -z "${ACKED:-}" ]; then
                    print_rows "$d/runs.json"
                    names="$(jq -r '[.check_runs[] | select(.status != "completed") | .name] | join("; ")' "$d/runs.json")"
                    echo "REVIEW_ACTION $VERDICT_LINE; still running: ${names:-(none)}${missing:+; missing: $missing}"
                    exit 4
                fi
            fi
        fi

        if [ -n "${REVIEW_FIRST:-}" ]; then
            # A failed reviewer falls through to the reviewer_failed block below (same FAILED line).
            rconc="$(jq -r --arg name "$REVIEWER_CHECK" '[.check_runs[] | select(.name == $name and .status == "completed"
                and (.conclusion as $c | ["success", "skipped"] | index($c)))] | if length > 0 then .[0].conclusion else empty end' "$d/runs.json")"
            if [ -n "$rconc" ]; then
                print_rows "$d/runs.json"
                names="$(jq -r '[.check_runs[] | select(.status != "completed") | .name] | join("; ")' "$d/runs.json")"
                echo "REVIEW_DONE $rconc; still running: ${names:-(none)}${missing:+; missing: $missing}"
                exit 0
            fi
        elif [ "$total" -gt 0 ] && [ "$pending" = 0 ] && [ -z "$missing" ]; then
            print_rows "$d/runs.json"
            names="$(jq -r '[.check_runs[] | select(.conclusion as $c | ["success", "skipped"] | index($c) | not) | .name] | join("; ")' "$d/runs.json")"
            if [ -z "$names" ]; then
                echo "ALL_GREEN"
                exit 0
            fi
            echo "FAILED $names"
            exit 1
        fi

        # A failed check ends the wait at once, whatever else still runs: the agent reads the failed log
        # and acts while the other jobs go on (tm-agent-loop, section 6). With --review-first or
        # --until-complete only the reviewer's check counts here.
        failed_names="$(jq -r --arg name "$REVIEWER_CHECK" --arg only "${REVIEW_FIRST:-}${UNTIL_COMPLETE:-}" '[.check_runs[]
            | select(.status == "completed" and (.conclusion as $c | ["success", "skipped"] | index($c) | not)
                and ($only == "" or .name == $name)) | .name] | join("; ")' "$d/runs.json")"
        if [ -n "$failed_names" ]; then
            print_rows "$d/runs.json"
            names="$(jq -r '[.check_runs[] | select(.status != "completed") | .name] | join("; ")' "$d/runs.json")"
            echo "FAILED $failed_names${names:+; still running: $names}${missing:+; missing: $missing}"
            exit 1
        fi

        if [ -n "${CALL_LIMIT:-}" ] && [ "$elapsed" -ge "$CALL_LIMIT" ] && [ "$elapsed" -lt "$MAX" ]; then
            print_rows "$d/runs.json"
            names="$(jq -r '[.check_runs[] | select(.status != "completed") | .name] | join("; ")' "$d/runs.json")"
            echo "PENDING ${names:-(none running)}${missing:+; missing: $missing}"
            exit 3
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
            WAIT_FOR_CHECKS_SELF_TEST=1 WAIT_FOR_CHECKS_VERDICT_CMD="$FIXTURES/verdict-stub" WAIT_FOR_CHECKS_MAX_SECONDS=3 WAIT_FOR_CHECKS_FAST_SECONDS=2 \
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
    "$0" --review-first > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --review-first without a PR or SHA does not exit 2"; failed=1; }
    # A leaked override of the verdict reader is ignored outside the self-test: with the stub (APPROVE) honored this
    # case would go on to ALL_GREEN (exit 0); with the real reader it needs the PR, which the fake gh does not serve.
    state="$(mktemp -d)"
    out="$(PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$FIXTURES/verdict-approve-keeps-waiting" FAKE_GH_STATE="$state" \
        WAIT_FOR_CHECKS_VERDICT_CMD="$FIXTURES/verdict-stub" WAIT_FOR_CHECKS_MAX_SECONDS=3 WAIT_FOR_CHECKS_FAST_SECONDS=2 \
        WAIT_FOR_CHECKS_FAST_STEP=1 WAIT_FOR_CHECKS_SLOW_STEP=1 "$0" 77 2>/dev/null)"; code=$?
    rm -rf "$state"
    if [ "$code" = 4 ] && printf '%s' "$out" | grep -q '^REVIEW_ACTION UNKNOWN'; then echo "ok   the verdict reader cannot be replaced outside the self-test"; else
        echo "FAIL a leaked WAIT_FOR_CHECKS_VERDICT_CMD was honored (exit $code): $out"; failed=1; fi
    "$0" --review-acked > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --review-acked without a PR or SHA does not exit 2"; failed=1; }
    "$0" --max-seconds > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --max-seconds without a value does not exit 2"; failed=1; }
    "$0" --max-seconds x 12 > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL a non-numeric --max-seconds does not exit 2"; failed=1; }
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
CALL_LIMIT=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --review-first) REVIEW_FIRST=1; shift ;;
        --until-complete) UNTIL_COMPLETE=1; shift ;;
        --review-acked) ACKED=1; shift ;;
        --max-seconds)
            [ "$#" -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
            case "$2" in '' | *[!0-9]*) echo "$USAGE" >&2; echo "--max-seconds takes whole seconds" >&2; exit 2 ;; esac
            [ "$2" -ge 1 ] || { echo "$USAGE" >&2; echo "--max-seconds must be at least 1" >&2; exit 2; }
            CALL_LIMIT="$2"; shift 2 ;;
        *) break ;;
    esac
done
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
