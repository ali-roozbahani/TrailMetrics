#!/usr/bin/env bash
# Writes `.review-verdict` (tm-pr-review, "Orchestrator's part", step 3) from the reviewer's report,
# after checking its format, so the session does not copy the verdict by hand.
#
#   scripts/local-review-record-verdict.sh            the report the SubagentStop hook recorded for HEAD
#   scripts/local-review-record-verdict.sh <file>     a report in a file (`-` = stdin), e.g. of a headless run
#   scripts/local-review-record-verdict.sh --self-test
#
# The report must be the reviewer's own: line 1 `VERDICT: APPROVE|CHANGES|ESCALATE_TO_HUMAN`, line 2
# `REVIEWED_SHA: <full sha>`, and that sha is HEAD. A `NO_VERDICT:` line, another sha, a malformed
# line 1 or 2, or no recorded report refuses (exit 1, nothing written). On success it writes
# `<sha> <VERDICT>` to the git dir's `.review-verdict` (never committed) and prints it. This only
# writes the older push hook's record; the push is allowed by the hook's own check of the recorded
# report and dispositions (scripts/local-review-gate.sh check), which this script does not replace.
# The recorded report is read from ${LOCAL_REVIEWS_DIR:-$HOME/agent-workspace/local-reviews}/<sha>/report.
#
# Exit: 0 written, 1 refused, 2 usage error. Bash 3.2 compatible.
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REVIEWS_DIR="${LOCAL_REVIEWS_DIR:-$HOME/agent-workspace/local-reviews}"
USAGE="usage: scripts/local-review-record-verdict.sh [<report file> | -] | --self-test"
SHA_RE='^([0-9a-f]{40}|[0-9a-f]{64})$'

refuse() { echo "local-review-record-verdict: refused: $*" >&2; exit 1; }

record() {
    local src="${1:-}" head file l1 l2 verdict reviewed out
    head="$(git rev-parse HEAD 2>/dev/null)" || refuse "not inside a git work tree"
    file="$(mktemp)"
    trap 'rm -f -- "$file"' RETURN
    if [ -z "$src" ]; then
        [ -f "$REVIEWS_DIR/$head/report" ] || refuse "no report is recorded for HEAD ${head:0:12}: the reviewer has not finished, or the SubagentStop hook did not capture it (scripts/local-review-gate.sh check $head says what is held)"
        head -c 200000 "$REVIEWS_DIR/$head/report" > "$file"
    elif [ "$src" = - ]; then
        head -c 200000 > "$file"
    else
        [ -f "$src" ] || refuse "'$src' is not a file"
        head -c 200000 "$src" > "$file"
    fi
    l1="$(sed -n 1p "$file")"
    l2="$(sed -n 2p "$file")"
    case "$l1" in NO_VERDICT:*) refuse "the reviewer answered '$l1'; fix the cause and ask again (no verdict is recorded)" ;; esac
    [[ "$l1" =~ ^VERDICT:\ (APPROVE|CHANGES|ESCALATE_TO_HUMAN)$ ]] || refuse "line 1 is not 'VERDICT: APPROVE|CHANGES|ESCALATE_TO_HUMAN' (got '${l1:0:60}')"
    verdict="${BASH_REMATCH[1]}"
    [[ "$l2" =~ ^REVIEWED_SHA:\ ([0-9a-f]{40}|[0-9a-f]{64})$ ]] || refuse "line 2 is not 'REVIEWED_SHA: <full sha>' (got '${l2:0:60}')"
    reviewed="${BASH_REMATCH[1]}"
    [ "$reviewed" = "$head" ] || refuse "the report is for ${reviewed:0:12}, HEAD is ${head:0:12}; review the current commit"
    out="$(git rev-parse --path-format=absolute --git-path .review-verdict)"
    printf '%s %s\n' "$head" "$verdict" > "$out"
    echo "$head $verdict"
}

self_test() {
    local tmp fails=0 repo sha out rc
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LOCAL_REVIEWS_DIR="$tmp/reviews"
    repo="$tmp/repo"
    git init -q "$repo"
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name t
    git -C "$repo" commit -q --allow-empty -m init
    sha="$(git -C "$repo" rev-parse HEAD)"
    check() { # check <description> <expected substring> <expected exit> <command...>
        local d="$1" want="$2" wantrc="$3"
        shift 3
        out="$("$@" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$wantrc" ] && printf '%s' "$out" | grep -qF -- "$want"; then
            echo "ok   $d"
        else
            echo "FAIL $d: expected exit $wantrc and '$want', got exit $rc:" >&2
            printf '%s\n' "$out" | sed 's/^/       /' >&2
            fails=$((fails + 1))
        fi
    }
    run() { (cd "$repo" && bash "$SELF" "$@"); }
    vfile="$repo/.git/.review-verdict"
    printf 'VERDICT: APPROVE\nREVIEWED_SHA: %s\nPROTECTED: none\nNo findings.\n' "$sha" > "$tmp/approve"
    printf 'VERDICT: ESCALATE_TO_HUMAN\nREVIEWED_SHA: %s\n1. [note] x\n' "$sha" > "$tmp/escalate"
    printf 'VERDICT: CHANGES\nREVIEWED_SHA: %s\n' "$sha" > "$tmp/changes"
    printf 'VERDICT: APPROVE\nREVIEWED_SHA: %040d\n' 1 > "$tmp/other"
    printf 'NO_VERDICT: INPUT_MISSING diff\n' > "$tmp/noverdict"
    printf "I'm writing up the review now.\nVERDICT: APPROVE\nREVIEWED_SHA: %s\n" "$sha" > "$tmp/narration"
    printf 'VERDICT: MAYBE\nREVIEWED_SHA: %s\n' "$sha" > "$tmp/maybe"
    printf 'VERDICT: APPROVE\nREVIEWED_SHA: abc123\n' > "$tmp/short"
    check "no recorded report refuses" "no report is recorded for HEAD" 1 run
    check "APPROVE from a file" "$sha APPROVE" 0 run "$tmp/approve"
    check "the verdict file holds sha and verdict" "$sha APPROVE" 0 cat "$vfile"
    rm -f "$vfile"
    check "ESCALATE_TO_HUMAN from stdin" "$sha ESCALATE_TO_HUMAN" 0 sh -c "cd '$repo' && bash '$SELF' - < '$tmp/escalate'"
    check "CHANGES is written too (the push hook blocks it)" "$sha CHANGES" 0 run "$tmp/changes"
    rm -f "$vfile"
    check "a report of another commit refuses" "the report is for" 1 run "$tmp/other"
    check "NO_VERDICT refuses" "no verdict is recorded" 1 run "$tmp/noverdict"
    check "narration before the verdict refuses" "line 1 is not" 1 run "$tmp/narration"
    check "an unknown verdict refuses" "line 1 is not" 1 run "$tmp/maybe"
    check "a short sha refuses" "line 2 is not" 1 run "$tmp/short"
    check "a missing file refuses" "is not a file" 1 run "$tmp/nope"
    check "nothing was written by the refusals" "absent" 0 sh -c "[ ! -e '$vfile' ] && echo absent"
    mkdir -p "$LOCAL_REVIEWS_DIR/$sha" && cp "$tmp/approve" "$LOCAL_REVIEWS_DIR/$sha/report"
    check "the recorded report for HEAD is used without an argument" "$sha APPROVE" 0 run
    check "usage error exits 2" "usage:" 2 bash "$SELF" a b
    if [ "$fails" = 0 ]; then echo "local-review-record-verdict.sh self-test: all passed"; else echo "local-review-record-verdict.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]
    exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    "") record "" ;;
    -) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; record - ;;
    -*) echo "$USAGE" >&2; exit 2 ;;
    *) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; record "$1" ;;
esac
