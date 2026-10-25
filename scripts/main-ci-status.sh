#!/bin/bash
# Prints the result of the CI runs that `push`es to `main` started (tm-pr-workflow, "Before starting").
# Nobody else reads them: a PR is green before the merge, and `main` can still be red after it,
# also after a merge the agent did not make.
#
#   scripts/main-ci-status.sh                 the latest completed `push` run of ci.yml on main
#   scripts/main-ci-status.sh --sha <sha>     the push run of that one commit (40 hex)
#   scripts/main-ci-status.sh --recent <n>    the last n (1 to 20) push runs, newest first (below)
#   scripts/main-ci-status.sh --ack <run id>  record that the owner accepts a red run (below)
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
#
# --recent <n> prints one line per run, newest first, then a summary line:
#   <run id> <merge SHA> <#PR|-> <conclusion|running> [failed: <job names>]
#   RECENT green=<n> red=<n> running=<n> unacknowledged-red=<n>
# The PR number is the `(#N)` that ends the commit subject (first line of the head commit message; the run title is cut short), `-` when there is none. A red run is
# failure, timed_out or startup_failure (its failed jobs are read); a run that is not completed is
# `running`; another conclusion (cancelled, ...) is printed and counted nowhere. The exit code is
# that of the newest run (0 green, 1 red, 3 running, 4 for another conclusion, no run, or any
# failed or unreadable `gh` read). A red run is unacknowledged when its id is above the stored
# acknowledged id.
#
# --ack <run id> stores the run id in ~/agent-workspace/main-ci-ack (outside the repo, created when
# missing; MAIN_CI_ACK_FILE replaces the path, for the self-test) and prints `ACK <stored id>`. It
# never lowers the stored id. Only the owner's "go on" after a red run is a reason to call it.
# Environment: MAIN_CI_STATUS_HEAD (a 40-hex SHA) replaces the local ref, for the self-test.
#
# --self-test runs every case in scripts/main-ci-status-fixtures/ against a fake `gh` (no network):
# a case directory holds `arg` (the arguments), `head` (origin/main's head), runs.json (the run list),
# jobs-<run id>.json (the jobs of a run), `expected` (the output), `expected-exit`, `ack` (the stored
# acknowledged id, when the case has one), and `gh-fail` for a `gh` that always fails or
# `gh-fail-jobs` for a `gh` that fails only on the jobs read.
# Bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/scripts/main-ci-status-fixtures"
USAGE="usage: scripts/main-ci-status.sh [--sha <sha> | --recent <n (1-20)> | --ack <run id>] | --self-test"
ACK_FILE="${MAIN_CI_ACK_FILE:-$HOME/agent-workspace/main-ci-ack}"

unknown() {
    echo "MAIN_UNKNOWN $1"
    exit 4
}

self_test() {
    local failed=0 dir name expected expected_exit actual code T
    T="$(mktemp -d)"
    trap 'rm -rf "$T"' EXIT
    for dir in "$FIXTURES"/*/; do
        name="$(basename "$dir")"
        expected="$(cat "$dir/expected")"
        expected_exit="$(cat "$dir/expected-exit")"
        rm -f "$T/ack"
        [ -e "$dir/ack" ] && cp "$dir/ack" "$T/ack"
        actual="$(PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$dir" MAIN_CI_STATUS_HEAD="$(cat "$dir/head")" MAIN_CI_ACK_FILE="$T/ack" \
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
    "$0" --recent > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --recent without a value does not exit 2"; failed=1; }
    "$0" --recent 0 > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --recent 0 does not exit 2"; failed=1; }
    "$0" --recent 21 > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --recent 21 does not exit 2"; failed=1; }
    "$0" --recent x > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --recent with a non-number does not exit 2"; failed=1; }
    "$0" --recent 5 extra > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --recent with an extra argument does not exit 2"; failed=1; }
    "$0" --ack > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --ack without a value does not exit 2"; failed=1; }
    "$0" --ack x > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL --ack with a non-number does not exit 2"; failed=1; }
    # --ack creates the file (and its directory), raises the id and never lowers it
    local ack="$T/sub/ack" out
    out="$(MAIN_CI_ACK_FILE="$ack" "$0" --ack 50 2>&1)"
    [ "$out" = "ACK 50" ] && [ "$(cat "$ack")" = "50" ] || { echo "FAIL --ack 50 on a missing file: $out"; failed=1; }
    out="$(MAIN_CI_ACK_FILE="$ack" "$0" --ack 40 2>&1)"
    [ "$out" = "ACK 50" ] && [ "$(cat "$ack")" = "50" ] || { echo "FAIL --ack 40 lowered the stored id: $out"; failed=1; }
    out="$(MAIN_CI_ACK_FILE="$ack" "$0" --ack 60 2>&1)"
    [ "$out" = "ACK 60" ] && [ "$(cat "$ack")" = "60" ] || { echo "FAIL --ack 60 did not raise the stored id: $out"; failed=1; }
    if [ "$failed" = 0 ]; then echo "main-ci-status: self-test passed"; else echo "main-ci-status: self-test FAILED"; fi
    exit "$failed"
}

if [ "${1:-}" = "--self-test" ] && [ "$#" = 1 ]; then
    self_test
fi

SHA=""
RECENT=""
if [ "$#" = 0 ]; then
    :
elif [ "$#" = 2 ] && [ "$1" = "--ack" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
    ID="$((10#$2))"
    OLD=0
    if [ -s "$ACK_FILE" ]; then
        OLD="$(tr -d '[:space:]' < "$ACK_FILE")"
        [[ "$OLD" =~ ^[0-9]+$ ]] || unknown "$ACK_FILE does not hold a run id"
    fi
    if [ "$ID" -gt "$((10#$OLD))" ]; then
        mkdir -p "$(dirname "$ACK_FILE")" && echo "$ID" > "$ACK_FILE" || unknown "cannot write $ACK_FILE"
        echo "ACK $ID"
    else
        echo "ACK $((10#$OLD))"
    fi
    exit 0
elif [ "$#" = 2 ] && [ "$1" = "--recent" ] && [[ "$2" =~ ^[0-9]+$ ]] && [ "$((10#$2))" -ge 1 ] && [ "$((10#$2))" -le 20 ]; then
    RECENT="$((10#$2))"
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

if [ -n "$RECENT" ]; then
    ACKED=0
    if [ -s "$ACK_FILE" ]; then
        ACKED="$(tr -d '[:space:]' < "$ACK_FILE")"
        [[ "$ACKED" =~ ^[0-9]+$ ]] || unknown "$ACK_FILE does not hold a run id"
        ACKED="$((10#$ACKED))"
    fi
    ROWS="$(jq -r --argjson n "$RECENT" '[.workflow_runs[]] | sort_by(.id) | reverse | .[0:$n][]
        | [.id, .head_sha,
           ((((.head_commit.message // "") | split("\n")[0] | [match("\\(#([0-9]+)\\)\\s*$").captures[0].string] | .[0]) // "-")),
           (if .status != "completed" then "running" else (.conclusion // "-") end)] | @tsv' "$D/runs.json")" \
        || unknown "the run list is not readable"
    [ -n "$ROWS" ] || unknown "no push run of ci.yml on main"
    GREEN=0 RED=0 RUNNING=0 UNACK=0 FIRST=""
    while IFS=$'\t' read -r RID RSHA RPR RCONC; do
        [[ "$RID" =~ ^[0-9]+$ && "$RSHA" =~ ^[0-9a-f]{40}$ ]] || unknown "a run of the list is not readable"
        [ -n "$FIRST" ] || FIRST="$RCONC"
        PRTXT="-"; [ "$RPR" = "-" ] || PRTXT="#$RPR"
        case "$RCONC" in
            success) GREEN=$((GREEN + 1)); echo "$RID $RSHA $PRTXT success" ;;
            running) RUNNING=$((RUNNING + 1)); echo "$RID $RSHA $PRTXT running" ;;
            failure | timed_out | startup_failure)
                gh api "repos/{owner}/{repo}/actions/runs/$RID/jobs?per_page=100" > "$D/jobs.json" 2>/dev/null \
                    || unknown "gh api failed reading the jobs of run $RID"
                jq -e '.jobs | type == "array"' "$D/jobs.json" > /dev/null 2>&1 || unknown "the job list of run $RID is not readable"
                NAMES="$(jq -r '[.jobs[] | select(.conclusion as $c | ["success", "skipped"] | index($c) | not) | .name] | join("; ")' "$D/jobs.json")"
                RED=$((RED + 1))
                [ "$RID" -gt "$ACKED" ] && UNACK=$((UNACK + 1))
                echo "$RID $RSHA $PRTXT $RCONC failed: ${NAMES:-(none listed)}"
                ;;
            *) echo "$RID $RSHA $PRTXT $RCONC" ;;
        esac
    done <<< "$ROWS"
    echo "RECENT green=$GREEN red=$RED running=$RUNNING unacknowledged-red=$UNACK"
    case "$FIRST" in
        success) exit 0 ;;
        running) exit 3 ;;
        failure | timed_out | startup_failure) exit 1 ;;
        *) exit 4 ;;
    esac
fi

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
