#!/usr/bin/env bash
# A mechanical copy of the reviewer's input checks (tm-pr-review, "Inputs"), for the self-test below. The
# reviewer itself is a model that reads the skill's prose; this script applies the same rules to a checkout
# so that a rule which would reject a checkout CI really builds is found before it is merged (#276 added a
# rule that rejected CI's tree, which has no .git, and every reviewer run answered NO_VERDICT).
#
#   scripts/review-input-check.sh <checkout dir> <input dir> <SHA> <BASE>
#   scripts/review-input-check.sh --self-test
#
# Prints `OK`, or `NO_VERDICT: <CODE>` for the first failing check, in the skill's order and with its codes:
#   INPUT_MISSING <file>      an input file (head, base, branch, status, commits, diff, protected, rule-changes) is missing
#   HEAD_OR_BASE_MISMATCH     `head` is not SHA, or `base` is not BASE
#   TREE_NOT_CLEAN            `status` is not empty
#   GIT_HEAD_MISMATCH         where the checkout has a `.git`: a directory (a clone) or a file (a linked worktree,
#                             `gitdir: <path>`, branches in the `commondir`), its HEAD does not name a branch whose
#                             SHA (loose ref, or packed-refs) is SHA; where there is no `.git` the check does not apply
#   CLASSIFIER_ERROR          `protected` does not start with `protected` or `unprotected`
# Exit 0 for OK, 1 for a NO_VERDICT, 2 for a usage error.
#
# --self-test builds, from a scratch repository, the checkouts the reviewer meets (a clone on its branch, a
# linked worktree on a branch, and the tree CI builds: `git checkout-index -a -f --prefix=` of the head's files,
# no .git, exactly as .github/workflows/pr-review.yml does) and runs the checks on each, then the failing
# cases; it also checks that the skill's closed list of codes is the one above, that the skill's
# GIT_HEAD_MISMATCH rule names all three checkout kinds, and that the workflow still builds the reviewer's tree
# without .git. It cannot tell whether the model reads a rule the way this script applies it; a change of a
# rule's meaning that keeps these phrases is for the reviewer of that change.
# Bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$ROOT/scripts/review-input-check.sh"
USAGE="usage: scripts/review-input-check.sh <checkout dir> <input dir> <SHA> <BASE> | --self-test"
CODES="INPUT_MISSING HEAD_OR_BASE_MISMATCH TREE_NOT_CLEAN GIT_HEAD_MISMATCH CLASSIFIER_ERROR"

sha_of_branch() { # sha_of_branch <common git dir> <branch>
    local common="$1" b="$2"
    if [ -f "$common/refs/heads/$b" ]; then
        tr -d '[:space:]' < "$common/refs/heads/$b"
    elif [ -f "$common/packed-refs" ]; then
        awk -v r="refs/heads/$b" '$2 == r { print $1; exit }' "$common/packed-refs"
    fi
}

git_head_matches() { # git_head_matches <checkout> <sha>: 0 ok or no .git, 1 mismatch
    local dir="$1" sha="$2" gitdir common head branch got first rel
    if [ -d "$dir/.git" ]; then
        gitdir="$dir/.git"; common="$dir/.git"
    elif [ -f "$dir/.git" ]; then
        first="$(head -n 1 "$dir/.git")"
        case "$first" in 'gitdir: '*) gitdir="${first#gitdir: }" ;; *) return 1 ;; esac
        [ -f "$gitdir/commondir" ] || return 1
        rel="$(tr -d '[:space:]' < "$gitdir/commondir")"
        case "$rel" in /*) common="$rel" ;; *) common="$gitdir/$rel" ;; esac
    else
        return 0
    fi
    [ -f "$gitdir/HEAD" ] || return 1
    head="$(head -n 1 "$gitdir/HEAD")"
    case "$head" in 'ref: refs/heads/'*) branch="${head#ref: refs/heads/}" ;; *) return 1 ;; esac
    got="$(sha_of_branch "$common" "$branch")"
    [ -n "$got" ] && [ "$got" = "$sha" ]
}

check() { # check <checkout> <input dir> <sha> <base>
    local dir="$1" in="$2" sha="$3" base="$4" f
    for f in head base branch status commits diff protected rule-changes; do
        [ -r "$in/$f" ] || { echo "NO_VERDICT: INPUT_MISSING $f"; return 1; }
    done
    [ "$(tr -d '[:space:]' < "$in/head")" = "$sha" ] && [ "$(tr -d '[:space:]' < "$in/base")" = "$base" ] \
        || { echo "NO_VERDICT: HEAD_OR_BASE_MISMATCH"; return 1; }
    [ ! -s "$in/status" ] || { echo "NO_VERDICT: TREE_NOT_CLEAN"; return 1; }
    git_head_matches "$dir" "$sha" || { echo "NO_VERDICT: GIT_HEAD_MISMATCH"; return 1; }
    case "$(head -c 11 "$in/protected")" in protected* | unprotected*) ;; *) echo "NO_VERDICT: CLASSIFIER_ERROR"; return 1 ;; esac
    echo OK
}

self_test() {
    local tmp fails=0 repo in sha base out rc wt tree
    tmp="$(cd "$(mktemp -d)" && pwd -P)"
    TMP_ROOT="$tmp"
    trap 'rm -rf -- "$TMP_ROOT"' EXIT
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    expect() { # expect <description> <expected output> <checkout> [<input dir>]
        out="$(check "$3" "${4:-$in}" "$sha" "$base")"
        if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$out'" >&2; fails=$((fails + 1)); fi
    }
    repo="$tmp/repo"
    git init -q -b main "$repo"
    git -C "$repo" config user.email t@example.com; git -C "$repo" config user.name t
    echo base > "$repo/a.txt"; git -C "$repo" add -A; git -C "$repo" commit -q -m base
    base="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" switch -q -c chore/x
    echo change > "$repo/b.txt"; git -C "$repo" add -A; git -C "$repo" commit -q -m change
    sha="$(git -C "$repo" rev-parse HEAD)"
    in="$tmp/input"; mkdir -p "$in"
    echo "$sha" > "$in/head"; echo "$base" > "$in/base"; echo chore/x > "$in/branch"; : > "$in/status"
    echo c > "$in/commits"; echo d > "$in/diff"; echo "unprotected" > "$in/protected"; echo none > "$in/rule-changes"

    # The checkouts the reviewer meets.
    expect "a clone on its branch" OK "$repo"
    git -C "$repo" pack-refs --all
    expect "a clone whose refs are packed" OK "$repo"
    git -C "$repo" switch -q main
    wt="$tmp/wt"; git -C "$repo" worktree add -q "$wt" chore/x
    expect "a linked worktree on its branch" OK "$wt"
    git -C "$wt" checkout -q --detach
    expect "a linked worktree on a detached HEAD" "NO_VERDICT: GIT_HEAD_MISMATCH" "$wt"
    # CI's tree: the head's files without .git, built as pr-review.yml builds it.
    tree="$tmp/tree"; mkdir -p "$tree"
    git -C "$wt" checkout -q chore/x
    (cd "$wt" && git checkout-index -a -f --prefix="$tree/")
    expect "CI's tree (the head's files, no .git)" OK "$tree"
    expect "the clone on the other branch" "NO_VERDICT: GIT_HEAD_MISMATCH" "$repo"
    echo bad > "$wt/.git"
    expect "a .git file without gitdir" "NO_VERDICT: GIT_HEAD_MISMATCH" "$wt"

    # The input checks.
    for f in head base branch status commits diff protected rule-changes; do
        mv "$in/$f" "$in/$f.off"
        expect "missing input $f" "NO_VERDICT: INPUT_MISSING $f" "$tree"
        mv "$in/$f.off" "$in/$f"
    done
    echo "$base" > "$in/head"
    expect "head is not SHA" "NO_VERDICT: HEAD_OR_BASE_MISMATCH" "$tree"
    echo "$sha" > "$in/head"
    echo " M x" > "$in/status"
    expect "a dirty status" "NO_VERDICT: TREE_NOT_CLEAN" "$tree"
    : > "$in/status"
    echo oops > "$in/protected"
    expect "a malformed protected file" "NO_VERDICT: CLASSIFIER_ERROR" "$tree"
    echo "protected" > "$in/protected"
    expect "a protected file" OK "$tree"

    # The skill and the workflow still say what the checks above assume.
    skill="$ROOT/.claude/skills/tm-pr-review/SKILL.md"
    listed="$(sed -n '/^Before reviewing, check all of these/,/^No other code and no free-text/p' "$skill" | sed -n 's/^- `\([A-Z_]*\)[ `:].*/\1/p' | tr '\n' ' ')"
    if [ "$listed" = "$CODES " ]; then echo "ok   the skill's closed list of codes is the script's"; else
        echo "FAIL the skill lists '$listed', the script checks '$CODES '" >&2; fails=$((fails + 1)); fi
    rule="$(sed -n '/^- `GIT_HEAD_MISMATCH`/,/^- `CLASSIFIER_ERROR`/p' "$skill")"
    for phrase in 'A directory' 'A file' 'no `.git` at all'; do
        if printf '%s' "$rule" | grep -qF -- "$phrase"; then echo "ok   the skill's GIT_HEAD_MISMATCH rule names: $phrase"; else
            echo "FAIL the skill's GIT_HEAD_MISMATCH rule does not name: $phrase" >&2; fails=$((fails + 1)); fi
    done
    if grep -qF 'git checkout-index -a -f --prefix=' "$ROOT/.github/workflows/pr-review.yml"; then echo "ok   the workflow builds the reviewer's tree without .git"; else
        echo "FAIL pr-review.yml no longer builds the tree with git checkout-index --prefix: update this self-test's CI tree" >&2; fails=$((fails + 1)); fi

    out="$(bash "$SELF" 2>&1)" && rc=0 || rc=$?
    if [ "$rc" = 2 ]; then echo "ok   a usage error exits 2"; else echo "FAIL usage error: exit $rc" >&2; fails=$((fails + 1)); fi
    if [ "$fails" -eq 0 ]; then echo "review-input-check self-test: all passed"; else echo "review-input-check self-test: $fails failed" >&2; fi
    [ "$fails" -eq 0 ]
}

if [ "${1:-}" = --self-test ]; then
    [ $# -eq 1 ] || { echo "$USAGE" >&2; exit 2; }
    self_test
    exit $?
fi
[ $# -eq 4 ] || { echo "$USAGE" >&2; exit 2; }
[ -d "$1" ] && [ -d "$2" ] || { echo "$USAGE" >&2; exit 2; }
out="$(check "$1" "$2" "$3" "$4")"
rc=$?
echo "$out"
exit "$rc"
