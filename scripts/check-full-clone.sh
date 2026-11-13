#!/usr/bin/env bash
# The clone is not shallow. A shallow clone has no history before its boundary commit, so the gate's
# merge-base with origin/main, the base of every diff check (classifier, protected paths, Room schema,
# board) and the IDE's log are wrong or missing. First step of pre-push-check.sh.
#
#   scripts/check-full-clone.sh [--root <dir>]  exit 0 = full clone (or CI), 1 = shallow, 2 = usage or not a repository
#   scripts/check-full-clone.sh --self-test     the cases below, in scratch clones
#
# CI's checkout is shallow on purpose (actions/checkout, depth 1): when GITHUB_ACTIONS is `true` a shallow
# clone passes with a note. Nothing else exempts it: CI's other variables (GITHUB_EVENT_NAME, GITHUB_BASE_REF,
# EVENT_NAME) set by hand in a real clone do not.
# Fix for a shallow clone: git fetch --unshallow
# Bash 3.2 compatible.
set -u

USAGE="usage: scripts/check-full-clone.sh [--root <dir>] | --self-test"

check() {
    local root="$1" shallow boundary
    shallow="$(git -C "$root" rev-parse --is-shallow-repository 2>/dev/null)" || {
        echo "check-full-clone: $root is not a git repository" >&2
        return 2
    }
    if [ "$shallow" != true ]; then
        echo "check-full-clone: the clone is full"
        return 0
    fi
    if [ "${GITHUB_ACTIONS:-}" = true ]; then
        echo "check-full-clone: the checkout is shallow, as CI's is (GITHUB_ACTIONS=true)"
        return 0
    fi
    boundary="$(git -C "$root" rev-parse --git-path shallow 2>/dev/null)"
    echo "check-full-clone: FAILED, this clone is shallow: its history ends at the commits listed in ${boundary:-.git/shallow}."
    echo "  The merge-base with origin/main and every base-compared check are wrong or missing."
    echo "  Fix: git fetch --unshallow   (then run this again; find what shallowed it with the clone's reflog and FETCH_HEAD)"
    return 1
}

self_test() {
    local tmp origin full shallow failed=0 out code
    tmp="$(mktemp -d)" || { echo "FAIL mktemp"; exit 1; }
    trap 'rm -rf -- "$tmp"' EXIT
    origin="$tmp/origin"
    g() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main -c gc.auto=0 "$@"; }
    g init -q "$origin" && g -C "$origin" commit -q --allow-empty -m one \
        && g -C "$origin" commit -q --allow-empty -m two \
        && g clone -q "file://$origin" "$tmp/full" && g clone -q --depth 1 "file://$origin" "$tmp/shallow" \
        || { echo "FAIL could not build the scratch repositories"; exit 1; }
    full="$tmp/full"; shallow="$tmp/shallow"
    mkdir "$tmp/plain"
    expect() { # name, want exit, text the output must contain, env assignments...
        local name="$1" want="$2" text="$3"; shift 3
        out="$(cd "$tmp" && env -u GITHUB_ACTIONS "$@" "$SELF" --root "$ROOT_UNDER_TEST" 2>&1)"; code=$?
        if [ "$code" = "$want" ] && [[ "$out" == *"$text"* ]]; then echo "ok   $name (exit $code)"
        else echo "FAIL $name: expected exit $want with '$text', got exit $code: $out"; failed=1; fi
    }
    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    ROOT_UNDER_TEST="$full"
    expect "full clone passes" 0 "the clone is full" A=1
    expect "full clone with CI's variables set by hand passes and stays full" 0 "the clone is full" \
        GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main EVENT_NAME=pull_request
    [ "$(g -C "$full" rev-parse --is-shallow-repository)" = false ] || { echo "FAIL the full clone became shallow"; failed=1; }
    ROOT_UNDER_TEST="$shallow"
    expect "shallow clone fails and names the fix" 1 "git fetch --unshallow" A=1
    expect "shallow clone with CI's other variables set by hand still fails" 1 "FAILED" \
        GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main EVENT_NAME=pull_request
    expect "shallow checkout in CI passes" 0 "as CI's is" GITHUB_ACTIONS=true
    ROOT_UNDER_TEST="$tmp/plain"
    expect "not a repository is a usage error" 2 "not a git repository" A=1
    "$SELF" --bogus > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL a usage error does not exit 2"; failed=1; }
    if [ "$failed" = 0 ]; then echo "check-full-clone: self-test passed"; else echo "check-full-clone: self-test FAILED"; fi
    exit "$failed"
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "${1:-}" in
    --self-test)
        [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }
        self_test ;;
    --root)
        [ "$#" = 2 ] || { echo "$USAGE" >&2; exit 2; }
        ROOT="$2" ;;
    "") ;;
    *) echo "$USAGE" >&2; exit 2 ;;
esac
check "$ROOT"
