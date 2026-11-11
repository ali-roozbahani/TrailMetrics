#!/usr/bin/env bash
# The local review that still holds for a PR's head (tm-agent-loop, merge condition 5), when the head
# is a merge-only update of a reviewed commit (GitHub's update of the branch,
# scripts/queue/update-branch.sh). Read-only.
#
#   scripts/queue/local-verdict-for-head.sh <PR number | head SHA (40 hex)>   in the repository of the cwd
#   scripts/queue/local-verdict-for-head.sh --self-test
#
# Starting at the head, it walks back to the first parent over commits that
# scripts/queue/merge-only-check.sh accepts, to the newest commit with a recorded local review
# (${LOCAL_REVIEWS_DIR:-$HOME/agent-workspace/local-reviews}/<sha>/report, written by
# scripts/local-review-gate.sh). That review counts only when its verdict is APPROVE and
# `scripts/local-review-gate.sh check <sha>` allows it (no [blocking], every [important] disposed).
# A commit with a recorded review ends the walk, whatever its verdict. At most 20 updates are walked.
#
# Given a PR number it reads the head SHA through REST (`gh api repos/{owner}/{repo}/pulls/<N>`);
# the head must be in the local clone (`git fetch origin` first).
#
# Output, one line:
#   APPROVE <reviewed sha> (<n> updates)    exit 0; n is the number of merge-only commits walked over
#   NONE <reason>                           exit 1: the review is not APPROVE or not allowed, a
#                                           commit on the way has no review and is not merge-only,
#                                           the head is not in the clone, more than 20 updates
# Exit 2: usage error, a failed `gh` call. Bash 3.2 compatible.
set -u -o pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
DIR="$(dirname "$SELF")"
GATE="$DIR/../local-review-gate.sh"
REVIEWS_DIR="${LOCAL_REVIEWS_DIR:-$HOME/agent-workspace/local-reviews}"
MAX_UPDATES=20
USAGE="usage: scripts/queue/local-verdict-for-head.sh <PR number | head SHA> | --self-test"

die() { echo "local-verdict-for-head: $*" >&2; exit 2; }
none() { echo "NONE $*"; exit 1; }

walk() {
    local c="$1" n=0 verdict reason
    git cat-file -e "$c^{commit}" 2>/dev/null || none "the head ${c:0:12} is not in the local clone (git fetch origin)"
    while :; do
        if [ -f "$REVIEWS_DIR/$c/report" ]; then
            verdict="$(sed -n 's/^VERDICT: //p;1q' "$REVIEWS_DIR/$c/report")"
            [ "$verdict" = APPROVE ] || none "the newest reviewed commit ${c:0:12} has verdict ${verdict:-UNKNOWN}, not APPROVE"
            reason="$(LOCAL_REVIEWS_DIR="$REVIEWS_DIR" bash "$GATE" check "$c" 2>&1 >/dev/null)" \
                || none "the review of ${c:0:12} does not allow a push: ${reason#Blocked: }"
            echo "APPROVE $c ($n updates)"
            exit 0
        fi
        reason="$(bash "$DIR/merge-only-check.sh" "$c" 2>&1)"
        case $? in
            0) ;;
            1) none "${c:0:12} has no recorded review and is not a merge-only update: ${reason#NOT_MERGE_ONLY $c }" ;;
            *) die "merge-only-check failed on ${c:0:12}: $reason" ;;
        esac
        n=$((n + 1))
        [ "$n" -le "$MAX_UPDATES" ] || none "more than $MAX_UPDATES merge-only updates above any review"
        c="$(git rev-parse "$c^1")" || die "cannot read the first parent of $c"
    done
}

self_test() {
    local tmp fails=0 out rc r H L U1 U2 C X
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp" LOCAL_REVIEWS_DIR="$tmp/reviews"
    mkdir -p "$tmp/bin"
    # A stub `gh` that answers the PR read with $STUB_HEAD, or fails with STUB_GH_FAIL.
    printf '%s\n' '#!/usr/bin/env bash' \
        '[ -z "${STUB_GH_FAIL:-}" ] || { echo "stub gh: failure" >&2; exit 1; }' \
        'case "$*" in "api repos/{owner}/{repo}/pulls/7 --jq .head.sha") echo "$STUB_HEAD" ;; *) echo "stub gh: unexpected $*" >&2; exit 1 ;; esac' \
        > "$tmp/bin/gh"
    chmod +x "$tmp/bin/gh"
    expect() { # expect <description> <expected output> <expected exit> <argument>
        out="$(cd "$r" && PATH="$tmp/bin:$PATH" bash "$SELF" "$4" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$3" ] && [ "$out" = "$2" ]; then echo "ok   $1"; else
            echo "FAIL $1: expected exit $3 and '$2', got exit $rc: $out" >&2; fails=$((fails + 1)); fi
    }
    review() { # review <sha> <verdict> [<finding line>]
        mkdir -p "$LOCAL_REVIEWS_DIR/$1"
        { echo "VERDICT: $2"; echo "REVIEWED_SHA: $1"; echo; [ -z "${3:-}" ] || echo "$3"; } > "$LOCAL_REVIEWS_DIR/$1/report"
    }
    . "$DIR/queue-fixtures/scratch-repo.sh"
    r="$tmp/repo"
    scratch_repo "$r"

    br pr main; edit f1 2 pr; H="$(g rev-parse HEAD)"
    expect "no review at all" "NONE ${H:0:12} has no recorded review and is not a merge-only update: has 1 parent(s), not 2" 1 "$H"
    review "$H" APPROVE
    expect "a reviewed head" "APPROVE $H (0 updates)" 0 "$H"
    main_commit f3 other; gm pr "update branch"; U1="$(g rev-parse HEAD)"
    expect "one merge-only update" "APPROVE $H (1 updates)" 0 "$U1"
    main_commit f4 other; gm pr "update branch"; U2="$(g rev-parse HEAD)"
    expect "two merge-only updates" "APPROVE $H (2 updates)" 0 "$U2"
    STUB_HEAD="$U2" expect "a PR number" "APPROVE $H (2 updates)" 0 7
    out="$(cd "$r" && STUB_GH_FAIL=1 PATH="$tmp/bin:$PATH" bash "$SELF" 7 2>&1)"; rc=$?
    [ "$rc" = 2 ] && echo "ok   a failed gh call exits 2" || { echo "FAIL a failed gh call: exit $rc: $out" >&2; fails=$((fails + 1)); }
    # a hand edit inside the update: not merge-only, no review
    main_commit f5 other; co pr; g merge -q --no-ff --no-commit main >/dev/null 2>&1; echo x >> "$r/f2"; g add f2; g commit -q -m "edited merge"
    X="$(g rev-parse HEAD)"
    expect "an edited merge is not walked over" "NONE ${X:0:12} has no recorded review and is not a merge-only update: its tree differs from the merge of its parents (edited by hand)" 1 "$X"
    # a new commit on top of an update, reviewed CHANGES
    br pr2 main; edit f1 4 pr2; C="$(g rev-parse HEAD)"; review "$C" CHANGES
    main_commit f6 other; gm pr2 "update branch"
    expect "the newest review is CHANGES" "NONE the newest reviewed commit ${C:0:12} has verdict CHANGES, not APPROVE" 1 "$(g rev-parse HEAD)"
    # APPROVE with an [important] finding and no disposition
    br pr3 main; edit f1 5 pr3; C="$(g rev-parse HEAD)"; review "$C" APPROVE "1. [important] something to dispose"
    out="$(cd "$r" && bash "$SELF" "$C" 2>&1)"; rc=$?
    case "$out" in "NONE the review of ${C:0:12} does not allow a push: "*"no dispositions are recorded"*) [ "$rc" = 1 ] ;; *) false ;; esac \
        && echo "ok   an undisposed [important] finding" || { echo "FAIL undisposed [important]: exit $rc: $out" >&2; fails=$((fails + 1)); }
    # the review of the commit below a merge that is not merge-only is not reached
    br pr4 main; edit f1 6 pr4; C="$(g rev-parse HEAD)"; review "$C" APPROVE
    br side4 main; edit f7 1 side; co pr4; g merge -q --no-ff -m "merge side" side4 >/dev/null
    X="$(g rev-parse HEAD)"
    expect "a merge of a non-main branch is not walked over" "NONE ${X:0:12} has no recorded review and is not a merge-only update: its second parent $(g rev-parse --short=12 side4) is not on origin/main" 1 "$X"
    expect "a head not in the clone" "NONE the head $(printf '%.12s' "$(printf 'e%.0s' $(seq 40))") is not in the local clone (git fetch origin)" 1 "$(printf 'e%.0s' $(seq 40))"
    out="$(bash "$SELF" abc 2>&1)"; [ $? = 2 ] && echo "ok   usage error exits 2" || { echo "FAIL usage error does not exit 2" >&2; fails=$((fails + 1)); }
    if [ "$fails" = 0 ]; then echo "local-verdict-for-head.sh self-test: all passed"; else echo "local-verdict-for-head.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]
    exit $?
}

[ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }
[ "$1" != --self-test ] || self_test
git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repository"
if [[ "$1" =~ ^[0-9a-f]{40}$ ]]; then
    walk "$1"
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    head="$(gh api "repos/{owner}/{repo}/pulls/$1" --jq .head.sha 2>/dev/null)" || die "gh api failed reading PR $1"
    [[ "$head" =~ ^[0-9a-f]{40}$ ]] || die "PR $1 has no head sha"
    walk "$head"
else
    echo "$USAGE" >&2; exit 2
fi
