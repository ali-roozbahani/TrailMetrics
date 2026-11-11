#!/usr/bin/env bash
# Sets the description of a pull request from a file, through the REST API: `gh pr edit` needs the
# `read:org` scope, which the machine account's token lacks, so this PATCHes
# repos/{owner}/{repo}/pulls/<N> with the body instead.
#
#   scripts/set-pr-body.sh <PR number> <body file>
#   scripts/set-pr-body.sh --print-body <body file>
#   scripts/set-pr-body.sh --self-test
#
# <body file> is the PR description draft, ~/agent-workspace/pr-body-<slug>.md. The body sent is
# the file as written, except that carriage returns are removed and an optional `Title:` first line
# and the blank line below it are dropped: the same text the PR is created with and the reviewer's
# TASK holds (scripts/review-task.sh reads it through --print-body, so the rule lives here once).
# The `Title:` line is not sent anywhere: this sets the description only, never the title.
#
# Prints the PR's URL and exits 0 when the call succeeded. Exit 1: the `gh` call failed (its error
# is printed). Exit 2: a usage error, a missing body file, or a missing tool.
#
# --self-test runs the cases in scripts/set-pr-body-fixtures/ against a fake `gh` (no network), and
# a CRLF case it writes itself: a case directory holds body.md, `expected` (the body the fake
# received) and `expected-exit`, and a `gh-fail` file for a `gh` that fails.
set -u

USAGE="usage: scripts/set-pr-body.sh <PR number> <body file> | --print-body <body file> | --self-test"

# The description as sent: CRs removed, an optional `Title:` first line and the blank line below
# it dropped.
print_body() {
    tr -d '\r' < "$1" | awk 'NR == 1 && /^Title:/ {t = 1; next} t && NR == 2 && /^[[:space:]]*$/ {next} {print}'
}

self_test() {
    local fixtures dir name state actual code expected_exit failed=0 self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    fixtures="$(dirname "$self")/set-pr-body-fixtures"
    for dir in "$fixtures"/*/; do
        name="$(basename "$dir")"
        state="$(mktemp -d)"
        PATH="$fixtures:$PATH" FAKE_GH_DIR="$dir" FAKE_GH_STATE="$state" "$self" 42 "$dir/body.md" > "$state/out" 2>&1
        code=$?
        expected_exit="$(cat "$dir/expected-exit")"
        actual="$(cat "$state/received" 2>/dev/null || echo "(no call)")"
        if [ "$code" = "$expected_exit" ] && [ "$actual" = "$(cat "$dir/expected")" ]; then
            echo "ok   $name (exit $code)"
        else
            echo "FAIL $name: expected exit $expected_exit and body:"
            sed 's/^/       /' "$dir/expected"
            echo "     got exit $code and body:"
            printf '%s\n' "$actual" | sed 's/^/       /'
            sed 's/^/     output: /' "$state/out"
            failed=1
        fi
        rm -rf -- "$state"
    done
    [ -n "${name:-}" ] || { echo "FAIL no cases in $fixtures"; failed=1; }
    # Carriage returns are removed. Written here, not as a fixture: git normalizes the line ends of
    # a committed file in this repo (core.autocrlf=input), so a fixture could not hold them.
    state="$(mktemp -d)"
    printf 'Title: t\r\n\r\n## What changed\r\nText.\r\n' > "$state/crlf.md"
    PATH="$fixtures:$PATH" FAKE_GH_DIR="$fixtures/title-dropped" FAKE_GH_STATE="$state" "$self" 42 "$state/crlf.md" > /dev/null 2>&1
    code=$?
    if [ "$code" = 0 ] && [ "$(cat "$state/received" 2>/dev/null)" = "$(printf '## What changed\nText.\n')" ] \
        && ! LC_ALL=C grep -q "$(printf '\r')" "$state/received"; then
        echo "ok   crlf-removed (exit $code)"
    else
        echo "FAIL crlf-removed: exit $code, body:"; od -c "$state/received" 2>/dev/null | sed 's/^/       /'
        failed=1
    fi
    rm -rf -- "$state"
    # usage errors exit 2 and never call gh
    state="$(mktemp -d)"
    PATH="$fixtures:$PATH" FAKE_GH_DIR="$fixtures/title-dropped" FAKE_GH_STATE="$state" "$self" > /dev/null 2>&1
    [ $? = 2 ] || { echo "FAIL no argument does not exit 2"; failed=1; }
    PATH="$fixtures:$PATH" FAKE_GH_DIR="$fixtures/title-dropped" FAKE_GH_STATE="$state" "$self" abc "$fixtures/title-dropped/body.md" > /dev/null 2>&1
    [ $? = 2 ] || { echo "FAIL a non-numeric PR does not exit 2"; failed=1; }
    PATH="$fixtures:$PATH" FAKE_GH_DIR="$fixtures/title-dropped" FAKE_GH_STATE="$state" "$self" 42 "$state/missing.md" > /dev/null 2>&1
    [ $? = 2 ] || { echo "FAIL a missing body file does not exit 2"; failed=1; }
    [ ! -e "$state/received" ] || { echo "FAIL a usage error called gh"; failed=1; }
    rm -rf -- "$state"
    if [ "$failed" = 0 ]; then echo "set-pr-body: self-test passed"; else echo "set-pr-body: self-test FAILED"; fi
    exit "$failed"
}

if [ "${1:-}" = "--self-test" ] && [ "$#" = 1 ]; then
    self_test
fi
if [ "${1:-}" = "--print-body" ] && [ "$#" = 2 ]; then
    [ -f "$2" ] || { echo "$USAGE" >&2; echo "no such file: $2" >&2; exit 2; }
    print_body "$2"
    exit 0
fi
if [ "$#" != 2 ] || ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "$USAGE" >&2
    exit 2
fi
[ -f "$2" ] || { echo "$USAGE" >&2; echo "no such file: $2" >&2; exit 2; }
for tool in gh jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "set-pr-body: $tool is not installed" >&2; exit 2; }
done

# The body goes in a JSON request body (jq -Rs keeps every byte of the text as one string), so no
# field type conversion of `gh api -F` can touch it.
print_body "$2" | jq -Rs '{body: .}' \
    | gh api --method PATCH "repos/{owner}/{repo}/pulls/$1" --input - --jq .html_url || {
    echo "set-pr-body: the PATCH of PR $1 failed; the description is unchanged" >&2
    exit 1
}
