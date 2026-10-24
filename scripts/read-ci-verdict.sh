#!/bin/bash
# Reads the CI reviewer's verdict for a head SHA from the annotation of its check run
# (`Review — pr-reviewer`). The check's conclusion is green for both APPROVE and
# ESCALATE_TO_HUMAN, so the verdict is the annotation prefix (tm-agent-loop, section 7).
#
#   scripts/read-ci-verdict.sh <PR number> <head SHA>
#   scripts/read-ci-verdict.sh --self-test
#
# Prints one line: APPROVE, ESCALATE_TO_HUMAN, CHANGES, or UNKNOWN <reason>. When the message
# carries a count of [important] findings (`APPROVE, 2 important.`) the line ends in
# `, <n> important` (`APPROVE, 2 important`); a message without a count prints the bare verdict.
# Exit 0 only for one of the three verdicts, which then comes from the one completed check run of
# THAT SHA with exactly one annotation titled `Review — pr-reviewer` whose level and message
# prefix agree and whose blob link names that SHA. Anything else is UNKNOWN and exits 1: only
# the line APPROVE or `APPROVE, <n> important` counts as an approval. Exit 2 is a usage error.
# The PR number is used to confirm that the PR's head is still <head SHA>; a moved head is UNKNOWN.
#
# --self-test runs every case in scripts/read-ci-verdict-fixtures/ against a fake `gh` (no
# network): a case directory holds runs.json, annotations.json, the expected output line and,
# for a `gh` that fails, an empty gh-fail file.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/scripts/read-ci-verdict-fixtures"
CHECK_NAME="Review — pr-reviewer"

unknown() {
    echo "UNKNOWN $1"
    exit 1
}

read_verdict() {
    local n="$1" sha="$2" d head run_id out
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' EXIT

    head="$(gh pr view "$n" --json headRefOid --jq .headRefOid 2>/dev/null)" || unknown "gh pr view failed"
    [ "$head" = "$sha" ] || unknown "PR head is ${head:-empty}, not $sha"

    gh api "repos/{owner}/{repo}/commits/$sha/check-runs?check_name=Review%20%E2%80%94%20pr-reviewer&filter=latest" \
        > "$d/runs.json" 2>/dev/null || unknown "gh api failed"
    run_id="$(jq -r --arg sha "$sha" --arg name "$CHECK_NAME" \
        '[.check_runs[] | select(.name == $name and .head_sha == $sha)] | if length == 1 then .[0].id else empty end' \
        "$d/runs.json" 2>/dev/null)" || unknown "check runs are not readable"
    if [ -n "$run_id" ]; then
        gh api "repos/{owner}/{repo}/check-runs/$run_id/annotations?per_page=100" \
            > "$d/annotations.json" 2>/dev/null || unknown "gh api failed"
    else
        echo '[]' > "$d/annotations.json"
    fi

    out="$(jq -n -r --arg sha "$sha" --arg name "$CHECK_NAME" \
        --slurpfile runs "$d/runs.json" --slurpfile ann "$d/annotations.json" '
        ($runs[0].check_runs | map(select(.name == $name and .head_sha == $sha))) as $r
        | if ($r | length) != 1 then "NOT_APPROVE: \($r | length) check runs for \($sha)"
          elif $r[0].status != "completed" then "NOT_APPROVE: check run is \($r[0].status)"
          else ($ann[0] | map(select(.title == $name))) as $a
          | if ($a | length) != 1 then "NOT_APPROVE: \($a | length) annotations with that title"
            elif ($a[0].blob_href | tostring | contains("/blob/\($sha)/") | not) then "NOT_APPROVE: annotation is not for \($sha)"
            else ($a[0].message | capture("^(?<v>APPROVE|ESCALATE_TO_HUMAN|CHANGES)(, (?<n>[0-9]+) important)?(?<sep>[.:])") // null) as $m
            | (if $m == null then ""
               elif ($m.n // "") == "" or ($m.n | tonumber) == 0 then ""
               else ", \($m.n | tonumber) important" end) as $imp
            | if $m != null and $a[0].annotation_level == "notice" and $m.v == "APPROVE" and $m.sep == "." then "APPROVE\($imp)"
            elif $m != null and $a[0].annotation_level == "warning" and $m.v == "ESCALATE_TO_HUMAN" and $m.sep == ":" then "ESCALATE_TO_HUMAN\($imp)"
            elif $m != null and $a[0].annotation_level == "failure" and $m.v == "CHANGES" and $m.sep == ":" then "CHANGES\($imp)"
            else "NOT_APPROVE: level \($a[0].annotation_level) and message \($a[0].message | .[0:30]) disagree"
            end
          end
          end' 2>/dev/null)" || unknown "check run data is not readable"

    case "$out" in
        APPROVE | ESCALATE_TO_HUMAN | CHANGES | \
        "APPROVE, "*" important" | "ESCALATE_TO_HUMAN, "*" important" | "CHANGES, "*" important") echo "$out"; exit 0 ;;
        "NOT_APPROVE: "*) unknown "${out#NOT_APPROVE: }" ;;
        *) unknown "unexpected result" ;;
    esac
}

self_test() {
    local sha=1111111111111111111111111111111111111111 failed=0 dir name expected actual
    for dir in "$FIXTURES"/*/; do
        name="$(basename "$dir")"
        expected="$(cat "$dir/expected")"
        actual="$(PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$dir" FAKE_GH_HEAD="$sha" "$0" 42 "$sha")"
        if [ "$actual" = "$expected" ]; then
            echo "ok   $name: $actual"
        else
            echo "FAIL $name: expected '$expected', got '$actual'"
            failed=1
        fi
    done
    # the PR's head moved on since the SHA was read
    actual="$(PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$FIXTURES/approve" FAKE_GH_HEAD=3333333333333333333333333333333333333333 "$0" 42 "$sha")"
    case "$actual" in
        "UNKNOWN PR head is 3333"*) echo "ok   head-moved: $actual" ;;
        *) echo "FAIL head-moved: got '$actual'"; failed=1 ;;
    esac
    # exit code: 0 only for a verdict
    PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$FIXTURES/approve" FAKE_GH_HEAD="$sha" "$0" 42 "$sha" >/dev/null
    [ $? = 0 ] || { echo "FAIL exit code of a verdict is not 0"; failed=1; }
    PATH="$FIXTURES:$PATH" FAKE_GH_DIR="$FIXTURES/running" FAKE_GH_HEAD="$sha" "$0" 42 "$sha" >/dev/null
    [ $? = 1 ] || { echo "FAIL exit code of UNKNOWN is not 1"; failed=1; }
    [ "$failed" = 0 ] && echo "read-ci-verdict: self-test passed" || echo "read-ci-verdict: self-test FAILED"
    exit "$failed"
}

if [ "${1:-}" = "--self-test" ] && [ "$#" = 1 ]; then
    self_test
fi
if [ "$#" != 2 ] || ! [[ "$1" =~ ^[0-9]+$ ]] || ! [[ "$2" =~ ^[0-9a-f]{40}$ ]]; then
    echo "usage: scripts/read-ci-verdict.sh <PR number> <head SHA (40 hex)> | --self-test" >&2
    exit 2
fi
for tool in gh jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is not installed" >&2; exit 2; }
done
read_verdict "$1" "$2"
