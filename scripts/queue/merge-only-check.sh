#!/usr/bin/env bash
# Proves that a merge commit only moved its branch's base: the update GitHub makes when it updates
# a PR branch (scripts/queue/update-branch.sh), so the local review of the commit below it still
# describes the PR (tm-agent-loop, merge condition 5; scripts/queue/local-verdict-for-head.sh).
#
#   scripts/queue/merge-only-check.sh [--base <ref>] <sha>    in the repository of the cwd
#   scripts/queue/merge-only-check.sh --self-test
#
# M is merge-only when all of these hold (checked in this order; the first failure is the reason):
#   1. M has exactly two parents (M^1 the branch, M^2 the base it was updated to);
#   2. M^2 is an ancestor of <base> (default origin/main): the update brought in only the base;
#   3. `git merge-tree --write-tree M^1 M^2` merges cleanly and its tree equals M's tree: nothing
#      was resolved or edited by hand;
#   4. the branch's own change has the same `git patch-id --stable` before and after:
#      diff(merge-base(M^1, M^2), M^1) and diff(M^2, M). A base that already held part of the
#      change, or that changed the context of a hunk, changes it.
# A dependent branch that merges its parent's squash merge is not merge-only (its own change loses
# the parent's part): such a merge gets a fresh gate and local review, it is not walked over.
#
# Output, one line: `MERGE_ONLY <sha>` (exit 0), `NOT_MERGE_ONLY <sha> <reason>` (exit 1).
# Exit 2: usage error, not a commit, git older than 2.38 (no merge-tree --write-tree).
# Read-only: writes only objects git merge-tree writes. Bash 3.2 compatible.
set -u -o pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
USAGE="usage: scripts/queue/merge-only-check.sh [--base <ref>] <sha> | --self-test"

die() { echo "merge-only-check: $*" >&2; exit 2; }

patch_id() { # patch_id <from> <to>: the stable patch-id of the diff, or "empty"
    local id
    id="$(git -c core.quotePath=false diff --no-ext-diff --no-textconv --no-color --no-renames --full-index --binary "$1" "$2" \
        | git patch-id --stable | cut -d' ' -f1)" || return 1
    echo "${id:-empty}"
}

check() {
    local base="$1" m p1 p2 n tree merged mb before after
    m="$(git rev-parse --verify --quiet "$2^{commit}")" || die "$2 is not a commit"
    n="$(git rev-list --parents -n 1 "$m" | wc -w | tr -d ' ')"
    n=$((n - 1))
    if [ "$n" != 2 ]; then
        echo "NOT_MERGE_ONLY $m has $n parent(s), not 2"; return 1
    fi
    p1="$(git rev-parse "$m^1")" && p2="$(git rev-parse "$m^2")" || die "cannot read the parents of $m"
    git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "base $base is not a commit (git fetch origin)"
    if ! git merge-base --is-ancestor "$p2" "$base"; then
        echo "NOT_MERGE_ONLY $m its second parent ${p2:0:12} is not on $base"; return 1
    fi
    merged="$(git merge-tree --write-tree --no-messages "$p1" "$p2" 2>/dev/null)"
    case $? in
        0) ;;
        1) echo "NOT_MERGE_ONLY $m the merge of its parents conflicts (resolved by hand)"; return 1 ;;
        *) die "git merge-tree --write-tree failed (git 2.38 or newer is needed)" ;;
    esac
    merged="$(printf '%s\n' "$merged" | head -1)"
    tree="$(git rev-parse "$m^{tree}")"
    if [ "$merged" != "$tree" ]; then
        echo "NOT_MERGE_ONLY $m its tree differs from the merge of its parents (edited by hand)"; return 1
    fi
    mb="$(git merge-base "$p1" "$p2")" || die "no merge base of ${p1:0:12} and ${p2:0:12}"
    before="$(patch_id "$mb" "$p1")" && after="$(patch_id "$p2" "$m")" || die "git patch-id failed"
    if [ "$before" != "$after" ]; then
        echo "NOT_MERGE_ONLY $m the branch's own change differs (patch-id ${before:0:12} before, ${after:0:12} after)"; return 1
    fi
    echo "MERGE_ONLY $m"
}

self_test() {
    local tmp fails=0 out rc r
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    r="$tmp/repo"
    expect() { # expect <description> <expected line prefix> <expected exit> <sha>
        out="$(cd "$r" && bash "$SELF" "$4" 2>&1)" && rc=0 || rc=$?
        case "$out" in
            "$2"*) [ "$rc" = "$3" ] && { echo "ok   $1"; return; } ;;
        esac
        echo "FAIL $1: expected exit $3 and '$2...', got exit $rc: $out" >&2
        fails=$((fails + 1))
    }
    . "$(dirname "$SELF")/queue-fixtures/scratch-repo.sh"
    scratch_repo "$r"

    # 1. clean merge of main into a branch
    br clean base; edit f1 2 clean; main_commit f3 "new file"
    gm clean "merge main"; expect "clean merge" "MERGE_ONLY" 0 "$(g rev-parse HEAD)"
    # 2. the child edited a file its parent changed; the parent was squash-merged; the child merged
    #    main locally (not merge-only: its own change lost the parent's part); then main moved and
    #    GitHub updated the branch (merge-only)
    br parent1 base; edit f1 18 parent
    br child1 parent1; edit f1 3 child; edit f2 2 child
    squash parent1
    gm child1 "merge main after the parent's squash"; L1="$(g rev-parse HEAD)"
    expect "dependent local merge after a squash is not merge-only" "NOT_MERGE_ONLY $L1 the branch's own change differs" 1 "$L1"
    main_commit f4 "other"
    gm child1 "update branch"; expect "branch edited a file the parent changed: update after the squash" "MERGE_ONLY" 0 "$(g rev-parse HEAD)"
    # 3. the parent got an extra commit after the child branched, before the squash
    br parent2 main; edit f2 5 parent; br child2 parent2; edit f1 12 child
    co parent2; edit f2 15 extra
    squash parent2
    gm child2 "merge main after the parent's squash"
    expect "parent got an extra commit before the squash: local merge" "NOT_MERGE_ONLY" 1 "$(g rev-parse HEAD)"
    main_commit f7 "other"
    gm child2 "update branch"; expect "parent got an extra commit before the squash: update" "MERGE_ONLY" 0 "$(g rev-parse HEAD)"
    # 4. a conflict resolved by hand
    br conflict main; edit f1 10 ours; main_edit f1 10 theirs
    co conflict; g merge -q main -m conflict >/dev/null 2>&1; printf 'resolved\n' > "$r/f1"; g add f1; g commit -q --no-edit
    expect "hand-resolved conflict" "NOT_MERGE_ONLY $(g rev-parse HEAD) the merge of its parents conflicts" 1 "$(g rev-parse HEAD)"
    # 5. a hand edit inside a clean merge
    br handedit main; edit f2 9 branch; main_commit f8 "other"
    co handedit; g merge -q --no-ff --no-commit main >/dev/null 2>&1; echo extra >> "$r/f2"; g add f2; g commit -q -m "merge with an edit"
    expect "hand edit inside the merge" "NOT_MERGE_ONLY $(g rev-parse HEAD) its tree differs" 1 "$(g rev-parse HEAD)"
    # 6. three parents
    br octo main; edit f1 4 octo; br side main; edit f9 1 side; main_commit f10 other
    co octo; g merge -q --no-ff -m octopus main side >/dev/null
    expect "three parents" "NOT_MERGE_ONLY $(g rev-parse HEAD) has 3 parent(s)" 1 "$(g rev-parse HEAD)"
    # 7. the base already held part of the branch's change: clean, same tree, other patch-id
    br partial main; edit f1 6 same; edit f2 12 mine; main_edit f1 6 same
    gm partial "merge main"; expect "changed own patch-id" "NOT_MERGE_ONLY $(g rev-parse HEAD) the branch's own change differs" 1 "$(g rev-parse HEAD)"
    # 8. a commit that is not a merge
    br single main; edit f1 7 single
    expect "a non-merge commit" "NOT_MERGE_ONLY $(g rev-parse HEAD) has 1 parent(s)" 1 "$(g rev-parse HEAD)"
    # 9. a second parent that is not on origin/main
    br notmain main; edit f1 8 x; br other main; edit f11 1 other
    co notmain; g merge -q --no-ff -m "merge other" other
    expect "second parent not on origin/main" "NOT_MERGE_ONLY $(g rev-parse HEAD) its second parent" 1 "$(g rev-parse HEAD)"

    expect "not a commit exits 2" "merge-only-check: nosuch is not a commit" 2 nosuch
    out="$(bash "$SELF" 2>&1)"; [ $? = 2 ] && echo "ok   usage error exits 2" || { echo "FAIL usage error does not exit 2" >&2; fails=$((fails + 1)); }
    if [ "$fails" = 0 ]; then echo "merge-only-check.sh self-test: all passed"; else echo "merge-only-check.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]
    exit $?
}

BASE=origin/main
case "${1:-}" in
    --self-test) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    --base) [ "$#" = 3 ] || { echo "$USAGE" >&2; exit 2; }; BASE="$2"; shift 2 ;;
esac
[ "$#" = 1 ] && [ -n "$1" ] || { echo "$USAGE" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repository"
check "$BASE" "$1"
