#!/usr/bin/env bash
# Deletes the local branches whose pull request is merged (tm-pr-workflow, "Before starting").
#
# For every local branch except `main` and the checked-out one:
#   gh pr list --head <branch> --state all --json number,state
#   - a MERGED PR (and no OPEN one): `git branch -D <branch>`. The repo squash-merges, so git
#     never sees the branch as merged: `git branch -d` and `--merged` would keep it.
#   - an OPEN PR, or no PR (a PR that was only closed counts as none): the branch is kept.
#
# Output: one line per branch, `<branch> <MERGED-deleted|OPEN #n|NO_PR>`, then one summary line.
#
# Usage:
#   scripts/prune-merged-branches.sh [--check]
#   scripts/prune-merged-branches.sh --self-test
#
# --check deletes nothing and prints the same lines, with `MERGED` in place of `MERGED-deleted`.
#
# Exit codes:
#   0  done (or, with --check, no merged branch is left)
#   1  --check only: at least one merged branch is left
#   2  usage error
#   4  unknown, with the reason on stderr (a failed `gh` call, output that is not JSON, a branch
#      that could not be deleted). Fail closed: unknown is not clean.
#
# scripts/claude-hooks/block-branch-create-while-merged-branches.sh runs `--check` before a
# branch is created.

set -euo pipefail

self_test() {
    local script tmp stub repo fails=0 out rc
    script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' RETURN
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp"

    # A stub `gh` that answers `pr list --head <branch> ...` from files named after the branch
    # (`/` becomes `_`); a branch without a file has no PR. STUB_GH_FAIL makes every call fail.
    stub="$tmp/bin"
    mkdir -p "$stub" "$tmp/prs"
    cat >"$stub/gh" <<'STUB'
#!/usr/bin/env bash
if [ -n "${STUB_GH_FAIL:-}" ]; then
    echo "stub gh: simulated failure" >&2
    exit 1
fi
head=""
while [ $# -gt 0 ]; do
    if [ "$1" = "--head" ]; then head="$2"; fi
    shift
done
f="$STUB_GH_DIR/${head//\//_}"
if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi
STUB
    chmod +x "$stub/gh"
    export PATH="$stub:$PATH" STUB_GH_DIR="$tmp/prs"

    repo="$tmp/repo"
    git init -q -b main "$repo"
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name t
    git -C "$repo" commit -q --allow-empty -m init
    for b in chore/merged-b open-b nopr-b closed-b cur-b; do git -C "$repo" branch "$b"; done
    git -C "$repo" switch -q cur-b
    echo '[{"number":3,"state":"MERGED"}]' >"$tmp/prs/chore_merged-b"
    echo '[{"number":7,"state":"OPEN"}]' >"$tmp/prs/open-b"
    echo '[{"number":8,"state":"CLOSED"}]' >"$tmp/prs/closed-b"
    echo '[{"number":9,"state":"MERGED"}]' >"$tmp/prs/cur-b" # the checked-out branch is never deleted

    has_branch() { git -C "$repo" show-ref --verify --quiet "refs/heads/$1"; }
    lacks_branch() { ! has_branch "$1"; }
    # run <args...>: runs the script in $repo, sets $out (stdout) and $rc.
    run() { rc=0; out="$(cd "$repo" && bash "$script" "$@" 2>"$tmp/err")" || rc=$?; }
    # check <name> <command...>: reports ok/FAIL for the command given.
    check() {
        local name="$1"; shift
        if "$@"; then echo "ok   $name"; else echo "FAIL $name" >&2; fails=$((fails + 1)); fi
    }
    contains() { printf '%s\n' "$out" | grep -qxF -- "$1"; }
    not_listed() { ! printf '%s\n' "$out" | grep -q "^$1 "; }
    last_line_is_summary() { printf '%s\n' "$out" | tail -n 1 | grep -q '^prune-merged-branches: '; }

    run --check
    check "--check exits 1 with a merged branch (got $rc)" test "$rc" = 1
    check "--check names the merged branch" contains "chore/merged-b MERGED"
    check "--check deletes nothing" has_branch chore/merged-b

    run
    check "run exits 0 (got $rc)" test "$rc" = 0
    check "merged branch is reported deleted" contains "chore/merged-b MERGED-deleted"
    check "merged branch is gone" lacks_branch chore/merged-b
    check "open branch is reported" contains "open-b OPEN #7"
    check "open branch is kept" has_branch open-b
    check "branch without a PR is reported" contains "nopr-b NO_PR"
    check "branch without a PR is kept" has_branch nopr-b
    check "branch with only a closed PR is kept" has_branch closed-b
    check "current branch is kept" has_branch cur-b
    check "current branch is not listed" not_listed cur-b
    check "main is kept" has_branch main
    check "main is not listed" not_listed main
    check "summary line is last" last_line_is_summary

    run --check
    check "--check exits 0 when none is merged (got $rc)" test "$rc" = 0

    git -C "$repo" branch late-merged-b
    echo '[{"number":11,"state":"MERGED"}]' >"$tmp/prs/late-merged-b"
    STUB_GH_FAIL=1 run --check
    check "gh failure exits 4 with --check (got $rc)" test "$rc" = 4
    check "gh failure gives a reason" test -s "$tmp/err"
    STUB_GH_FAIL=1 run
    check "gh failure exits 4 (got $rc)" test "$rc" = 4
    check "gh failure deletes nothing" has_branch late-merged-b

    echo 'not json' >"$tmp/prs/open-b"
    run --check
    check "unreadable gh output exits 4 (got $rc)" test "$rc" = 4

    run --bogus
    check "unknown option exits 2 (got $rc)" test "$rc" = 2

    if [ "$fails" -ne 0 ]; then
        echo "prune-merged-branches.sh self-test: $fails failed" >&2
        return 1
    fi
    echo "prune-merged-branches.sh self-test: all passed"
}

MODE=prune
case "${1:-}" in
    "") ;;
    --self-test) self_test; exit $? ;;
    --check) MODE=check ;;
    *) echo "usage: $0 [--check | --self-test]" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
    echo "usage: $0 [--check | --self-test]" >&2
    exit 2
fi

fail() {
    echo "prune-merged-branches: $*" >&2
    exit 4
}

command -v gh >/dev/null 2>&1 || fail "gh is not installed"
command -v jq >/dev/null 2>&1 || fail "jq is not installed"

CURRENT="$(git branch --show-current 2>/dev/null)" || fail "not inside a git work tree"
BRANCHES="$(git for-each-ref --format='%(refname:short)' refs/heads)" || fail "could not list the local branches"

merged=0
kept=0
while IFS= read -r branch; do
    [ -n "$branch" ] || continue
    [ "$branch" = main ] && continue
    [ "$branch" = "$CURRENT" ] && continue

    prs="$(gh pr list --head "$branch" --state all --json number,state 2>&1)" \
        || fail "gh pr list failed for $branch: $prs"
    status="$(printf '%s' "$prs" | jq -r '
        if any(.[]; .state == "OPEN") then "OPEN #\(first(.[] | select(.state == "OPEN")).number)"
        elif any(.[]; .state == "MERGED") then "MERGED"
        else "NO_PR" end' 2>&1)" || fail "gh pr list gave unreadable output for $branch: $status"

    if [ "$status" = MERGED ]; then
        merged=$((merged + 1))
        if [ "$MODE" = prune ]; then
            deleted="$(git branch -D "$branch" 2>&1)" || fail "could not delete $branch: $deleted"
            status="MERGED-deleted"
        fi
    else
        kept=$((kept + 1))
    fi
    echo "$branch $status"
done <<<"$BRANCHES"

if [ "$MODE" = check ]; then
    echo "prune-merged-branches: check: $merged merged branch(es) left, $kept kept"
    [ "$merged" -eq 0 ] || exit 1
else
    echo "prune-merged-branches: $merged deleted, $kept kept"
fi
