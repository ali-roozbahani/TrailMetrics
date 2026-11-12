#!/usr/bin/env bash
# Prepares the local pr-reviewer run (tm-pr-review, "Orchestrator's part", steps 1 and 2) in one
# command: fills the review input directory from git and writes the reviewer's whole message to a
# file in it, so the session pastes neither the input block nor the ~7 KB message by hand.
#
#   scripts/local-review-prepare.sh <body file>     <body file> = the draft PR description,
#                                                   ~/agent-workspace/pr-body-<slug>.md
#   scripts/local-review-prepare.sh --self-test
#
# Run it from the repository after the last commit (the working tree must be clean). It writes, in
# the review input directory (`git rev-parse --git-path review-input`): head, base, branch, status,
# commits, diff, protected, rule-changes (the files the reviewer's Inputs list) and `message`, the
# output of scripts/review-task.sh <body file> (SHA, BASE, INPUT_DIR and TASK, as CI's reviewer gets
# them). It then prints the two-line prompt to give the reviewer (Agent tool, subagent_type
# pr-reviewer): `SHA:` (the SubagentStop hook reads the commit from that line) and `MESSAGE_FILE:`
# (the reviewer reads the file; tm-pr-review, "Inputs"). Exit 0 prepared, 1 refused (reason on
# stderr), 2 usage error.
#
# Bash 3.2 compatible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
USAGE="usage: scripts/local-review-prepare.sh <body file> | --self-test"

refuse() { echo "local-review-prepare: refused: $*" >&2; exit 1; }

prepare() {
    local body="$1" sha base in rc_on_base rc status
    [ -f "$body" ] || refuse "the PR description draft '$body' does not exist"
    git rev-parse --git-dir >/dev/null 2>&1 || refuse "not inside a git work tree"
    status="$(git status --porcelain)"
    [ -z "$status" ] || refuse "the working tree is not clean (git status --porcelain is not empty); commit first"
    sha="$(git rev-parse HEAD)"
    base="$(git merge-base HEAD origin/main)" || refuse "no merge-base with origin/main (git fetch origin first)"
    in="$(git rev-parse --path-format=absolute --git-path review-input)"
    mkdir -p "$in"
    rm -f -- "${in:?}/head" "${in:?}/base" "${in:?}/branch" "${in:?}/status" "${in:?}/commits" \
        "${in:?}/diff" "${in:?}/protected" "${in:?}/rule-changes" "${in:?}/message"
    echo "$sha" > "$in/head"
    echo "$base" > "$in/base"
    git rev-parse --abbrev-ref HEAD > "$in/branch"
    printf '%s' "$status" > "$in/status"
    git log --reverse --format='commit %H%n%B' --name-status "$base..$sha" > "$in/commits"
    git diff --no-color --find-renames "$base" "$sha" > "$in/diff"
    "$SCRIPT_DIR/check-protected-paths.sh" --base "$base" > "$in/protected" 2>&1
    # rule-changes: the script as it is on BASE, never the working tree's copy. If it can't be
    # read or fails, no file is written and the reviewer answers NO_VERDICT: INPUT_MISSING.
    if ! rc_on_base="$(git ls-tree --name-only "$base" scripts/check-skill-rule-changes.sh)"; then
        echo "local-review-prepare: rule-changes: cannot read $base" >&2
    elif [ -z "$rc_on_base" ]; then
        echo 'none (script not on the base)' > "$in/rule-changes"
    else
        rc="$(mktemp -d)"
        if git archive "$base" -- scripts/check-skill-rule-changes.sh scripts/check-skill-rule-changes.py \
            | tar -x -C "$rc" && bash "$rc/scripts/check-skill-rule-changes.sh" "$base" "$sha" > "$rc/out"; then
            mv -- "$rc/out" "$in/rule-changes"
        else
            echo "local-review-prepare: rule-changes: the script failed on $base" >&2
        fi
        rm -rf -- "$rc"
    fi
    "$SCRIPT_DIR/review-task.sh" "$body" > "$in/message.tmp"
    mv -- "$in/message.tmp" "$in/message"
    echo "prepared the review of $sha (base $base)"
    echo "input directory: $in"
    echo "message file: $in/message ($(wc -c < "$in/message" | tr -d ' ') bytes)"
    echo "Start the reviewer (Agent tool, subagent_type pr-reviewer) with exactly this prompt and nothing else:"
    echo "---"
    printf 'SHA: %s\nMESSAGE_FILE: %s\n' "$sha" "$in/message"
    echo "---"
    [ -s "$in/rule-changes" ] || echo "WARNING: $in/rule-changes was not written; the reviewer will answer NO_VERDICT: INPUT_MISSING rule-changes" >&2
}

self_test() {
    local tmp fails=0 repo out rc
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
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
    # A scratch repository with an origin, the scripts this one calls, and one commit on a branch.
    repo="$tmp/repo"
    git init -q --bare "$tmp/origin.git"
    git init -q -b main "$repo"
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name t
    mkdir -p "$repo/scripts" "$repo/.github"
    for f in local-review-prepare.sh review-task.sh set-pr-body.sh check-protected-paths.sh check-protected-paths.py; do
        cp "$SCRIPT_DIR/$f" "$repo/scripts/$f"
    done
    printf '/scripts/ @owner\n' > "$repo/.github/CODEOWNERS"
    printf '# Board\n\n## Tasks\n\n### gone-task\n- Type: task\n' > "$repo/BOARD.md"
    git -C "$repo" add -A && git -C "$repo" commit -q -m base
    git -C "$repo" remote add origin "$tmp/origin.git"
    git -C "$repo" push -q origin main 2>/dev/null
    git -C "$repo" fetch -q origin
    git -C "$repo" switch -q -c chore/x
    echo hello > "$repo/a.txt"
    git -C "$repo" add -A && git -C "$repo" commit -q -m "chore: add a"
    printf 'What changed\n\nBoard: -gone-task\n' > "$tmp/body.md"
    local sha
    sha="$(git -C "$repo" rev-parse HEAD)"
    run() { (cd "$repo" && bash scripts/local-review-prepare.sh "$@"); }
    check "prepares a clean committed branch" "SHA: $sha" 0 run "$tmp/body.md"
    local in="$repo/.git/review-input"
    check "head file holds the SHA" "$sha" 0 cat "$in/head"
    check "diff file holds the change" "+hello" 0 cat "$in/diff"
    check "protected file says unprotected" "unprotected" 0 cat "$in/protected"
    check "rule-changes file is written" "none (script not on the base)" 0 cat "$in/rule-changes"
    check "message file starts with SHA" "SHA: $sha" 0 cat "$in/message"
    check "message file carries the description" "Board: -gone-task" 0 cat "$in/message"
    check "message file carries the board record" "### gone-task" 0 cat "$in/message"
    check "a missing draft is refused" "refused: the PR description draft" 1 run "$tmp/none.md"
    echo dirty > "$repo/b.txt"
    check "a dirty tree is refused" "working tree is not clean" 1 run "$tmp/body.md"
    check "usage error exits 2" "usage:" 2 bash "$SELF"
    if [ "$fails" = 0 ]; then echo "local-review-prepare.sh self-test: all passed"; else echo "local-review-prepare.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]
    exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    "" | -*) echo "$USAGE" >&2; exit 2 ;;
    *) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; prepare "$1" ;;
esac
