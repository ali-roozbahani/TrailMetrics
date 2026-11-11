#!/usr/bin/env bash
# The base commit a CI step compares the pull request with: the one place that validates
# PR_BASE_SHA and fetches it when the checkout lacks it. scripts/classify-changes.sh --github
# and the "Kover floors check" and "Room schema check" steps of .github/workflows/ci.yml call it.
#
#   scripts/ci/pr-base.sh [--root <dir>]   EVENT_NAME and PR_BASE_SHA from the workflow's env
#   scripts/ci/pr-base.sh --self-test      the cases in scripts/ci/pr-base-fixtures/
#
# EVENT_NAME and PR_BASE_SHA come from the workflow's env (`github.event_name`,
# `github.event.pull_request.base.sha`), never from interpolated event text. --root runs git in
# another repository (default: the current directory).
#
# Exit and output:
#   0  pull_request, and the base is a commit here (fetched at depth 1 when it was missing):
#      prints the SHA
#   3  no base: any other event (push, workflow_dispatch, ...); prints nothing, says why on stderr
#   4  pull_request, and PR_BASE_SHA is not a commit SHA (40 or 64 hex)
#   1  pull_request, and the base is not a commit here even after the fetch
#   2  usage error
# Callers: 3 is "nothing to compare with" (a step skips, the classifier says full); every other
# non-zero exit is a failure (a step fails, the classifier says full).
#
# --self-test: each case directory holds `env` (EVENT_NAME=..., PR_BASE_SHA=... lines, where
# {BASE} is the base commit and {UNFETCHED} a commit only the origin has), `expect-exit` and, for
# exit 0, `expect-base` ({BASE} or {UNFETCHED}). The cases run in a scratch clone of a scratch
# origin, so the fetch is real and local.
# Bash 3.2 compatible.
set -u

USAGE="usage: scripts/ci/pr-base.sh [--root <dir>] | --self-test"

pr_base() {
    local root="$1" event="${EVENT_NAME:-}" base="${PR_BASE_SHA:-}"
    if [ "$event" != pull_request ]; then
        echo "pr-base: a '${event:-<unset>}' event has no base commit" >&2
        return 3
    fi
    if [[ ! "$base" =~ ^[0-9a-f]{40}$ ]] && [[ ! "$base" =~ ^[0-9a-f]{64}$ ]]; then
        echo "pr-base: PR_BASE_SHA is not a commit SHA" >&2
        return 4
    fi
    if ! git -C "$root" cat-file -e "$base^{commit}" 2>/dev/null; then
        git -C "$root" fetch --no-tags --quiet --depth=1 origin "$base" >&2 || true
    fi
    if ! git -C "$root" cat-file -e "$base^{commit}" 2>/dev/null; then
        echo "pr-base: $base is not a commit here, even after a fetch from origin" >&2
        return 1
    fi
    printf '%s\n' "$base"
}

self_test() {
    local self fixtures tmp origin clone base unfetched failed=0 dir name want_exit want_base out code line
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    fixtures="$(dirname "$self")/pr-base-fixtures"
    tmp="$(mktemp -d)" || { echo "FAIL mktemp"; exit 1; }
    trap 'rm -rf -- "$tmp"' EXIT
    origin="$tmp/origin"
    clone="$tmp/clone"
    g() { git -c user.name=pr-base-self-test -c user.email=self-test@example.invalid \
        -c init.defaultBranch=main -c gc.auto=0 "$@"; }
    g init -q "$origin" && g -C "$origin" commit -q --allow-empty -m base \
        && base="$(g -C "$origin" rev-parse HEAD)" \
        && g -C "$origin" commit -q --allow-empty -m later \
        && unfetched="$(g -C "$origin" rev-parse HEAD)" \
        || { echo "FAIL could not build the scratch repositories"; exit 1; }
    for dir in "$fixtures"/*/; do
        name="$(basename "$dir")"
        want_exit="$(cat "$dir/expect-exit")"
        want_base="$(sed "s/{BASE}/$base/; s/{UNFETCHED}/$unfetched/" "$dir/expect-base" 2>/dev/null || true)"
        # A fresh repository per case whose only commit is {BASE}, with the scratch origin as
        # `origin`: {UNFETCHED} is only on origin, and an earlier case's fetch cannot satisfy a
        # later one.
        rm -rf -- "$clone" && g init -q "$clone" && g -C "$clone" fetch -q --depth=1 "file://$origin" "$base" \
            && g -C "$clone" remote add origin "file://$origin" \
            || { echo "FAIL $name: could not build the clone"; failed=1; continue; }
        out="$(
            unset EVENT_NAME PR_BASE_SHA
            while IFS= read -r line || [ -n "$line" ]; do
                [ -n "$line" ] || continue
                line="${line//\{BASE\}/$base}"
                line="${line//\{UNFETCHED\}/$unfetched}"
                export "${line?}"
            done < "$dir/env"
            "$self" --root "$clone" 2>/dev/null
        )"
        code=$?
        if [ "$code" = "$want_exit" ] && [ "$out" = "$want_base" ]; then
            echo "ok   $name (exit $code)"
        else
            echo "FAIL $name: expected exit $want_exit and '${want_base}', got exit $code and '$out'"
            failed=1
        fi
    done
    "$self" --bogus > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL a usage error does not exit 2"; failed=1; }
    if [ "$failed" = 0 ]; then echo "pr-base: self-test passed"; else echo "pr-base: self-test FAILED"; fi
    exit "$failed"
}

ROOT="."
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
pr_base "$ROOT"
