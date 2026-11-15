#!/usr/bin/env bash
# Workflow guard (gate step): the agent pushes every change under .github/workflows/ itself, except two
# cases that only the owner pushes (owner decision of 2026-11-15; tm-agent-loop, section 5):
#   1. a diff that touches .github/workflows/pr-review.yml (that file holds the reviewer's API key step, and a
#      pull_request run uses the file as it is on the PR head);
#   2. a diff that adds a reference to `secrets` in any workflow file (`secrets.NAME`, `secrets[...]`,
#      `secrets:` as in `secrets: inherit`, a bare `${{ secrets }}`, `toJSON(secrets)`, in any case). A full-line comment is not a reference; a
#      removed reference alone is not a violation.
# Any other workflow change passes, the removal of CI's UI jobs included. The push hook allows a push only after
# the gate passed, so a failing guard keeps such a branch from being pushed by the agent.
#
#   scripts/check-workflow-guard.sh [--repo <dir>] --base <ref> [--head <ref>]
#                                     compare <ref> (the merge-base) with HEAD (or --head); committed trees only
#   scripts/check-workflow-guard.sh --self-test
#
# Exit 0 when the diff passes, 1 for a violation (messages on stderr), 2 for a usage or git error, which
# callers treat as a failure, never as a pass.
set -uo pipefail

PR_REVIEW=".github/workflows/pr-review.yml"
# `secrets` as a whole word (any case: context names are case-insensitive), then optional spaces and a dot,
# a bracket, a colon, a closing brace or parenthesis, a comma or the end of the line: `secrets.X`, `secrets['x']`,
# `secrets: inherit`, `${{ secrets }}`, `toJSON(secrets)`.
SECRETS_RE='(^|[^A-Za-z0-9_])secrets[[:space:]]*(\.|\[|:|\}|\)|,|$)'

usage() { sed -n '2,19p' "$0" >&2; exit 2; }

guard() {
    local repo="$1" base="$2" head="$3"
    local files file lines added stripped status violations=0
    git -C "$repo" rev-parse --verify --quiet "$base^{commit}" >/dev/null || { echo "check-workflow-guard: unknown base: $base" >&2; return 2; }
    git -C "$repo" rev-parse --verify --quiet "$head^{commit}" >/dev/null || { echo "check-workflow-guard: unknown head: $head" >&2; return 2; }
    files="$(git -C "$repo" diff --no-renames --name-only "$base" "$head" -- .github/workflows)" || return 2
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        case "$file" in
            .github/workflows/*.yml|.github/workflows/*.yaml) ;;
            *) continue ;;
        esac
        if [ "$file" = "$PR_REVIEW" ]; then
            echo "workflow guard: this branch changes $file; the owner pushes changes to that file, the agent does not. Do not push: hand the change over as a patch (tm-agent-loop, section 5)." >&2
            violations=1
        fi
        added="$(git -C "$repo" diff -U0 --no-renames "$base" "$head" -- "$file")" || return 2
        # Added lines only, without full-line comments. A grep status of 1 is "no match"; anything else is an error
        # and fails the check (a swallowed error would let every diff pass).
        stripped="$(printf '%s\n' "$added" | awk '/^@@/ {inhunk = 1; next} inhunk && /^\+/ {print substr($0, 2)}' | { grep -vE '^[[:space:]]*#' || [ $? -eq 1 ]; })" || return 2
        lines="$(printf '%s\n' "$stripped" | grep -niE "$SECRETS_RE")"
        status=$?
        [ "$status" -le 1 ] || { echo "check-workflow-guard: grep failed (status $status)" >&2; return 2; }
        if [ -n "$lines" ]; then
            echo "workflow guard: this branch adds a reference to secrets in $file; the owner pushes a change that reads a secret, the agent does not. Do not push: hand the change over as a patch (tm-agent-loop, section 5). Added lines (number among the added ones: text):" >&2
            printf '%s\n' "$lines" | sed 's/^/    /' >&2
            violations=1
        fi
    done <<<"$files"
    if [ "$violations" -eq 0 ]; then
        echo "check-workflow-guard: OK, no change to $PR_REVIEW and no added reference to secrets in a workflow file"
        return 0
    fi
    return 1
}

self_test() {
    local self fails=0 tmp
    self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    local r="$tmp/repo"
    git init -q "$r"
    git -C "$r" config user.email t@example.invalid
    git -C "$r" config user.name t
    mkdir -p "$r/.github/workflows"
    printf 'name: CI\njobs:\n  a:\n    steps:\n      - run: echo a\n' > "$r/.github/workflows/ci.yml"
    printf 'name: Review\njobs:\n  r:\n    env:\n      KEY: ${{ secrets.ANTHROPIC_API_KEY }}\n' > "$r/.github/workflows/pr-review.yml"
    printf 'name: Old\njobs:\n  o:\n    env:\n      T: ${{ secrets.OLD_TOKEN }}\n' > "$r/.github/workflows/old.yml"
    printf 'readme\n' > "$r/README.md"
    git -C "$r" add -A && git -C "$r" commit -q -m base && git -C "$r" tag base

    # case <name> <expected exit> <message fragment or ""> <mutation as a shell snippet run in the repo>
    case_() {
        local name="$1" want="$2" frag="$3" mutate="$4" out got
        git -C "$r" checkout -q -f base && git -C "$r" clean -fdq
        git -C "$r" checkout -q -b "c-$name"
        (cd "$r" && eval "$mutate")
        git -C "$r" add -A && git -C "$r" commit -q -m "$name" --allow-empty
        out="$("$self" --repo "$r" --base base 2>&1)"; got=$?
        if [ "$got" -eq "$want" ] && { [ -z "$frag" ] || printf '%s' "$out" | grep -qF -- "$frag"; }; then
            echo "ok   $name (exit $got)"
        else
            echo "FAIL $name: wanted exit $want${frag:+ and \"$frag\"}, got $got: $out"
            fails=$((fails + 1))
        fi
    }

    case_ pr-review-comment-only            1 "the owner pushes changes to that file" 'echo "# a comment" >> .github/workflows/pr-review.yml'
    case_ pr-review-deleted                 1 "the owner pushes changes to that file" 'git rm -q .github/workflows/pr-review.yml'
    case_ secrets-added-to-ci               1 "adds a reference to secrets in .github/workflows/ci.yml" 'echo "      - run: echo \${{ secrets.NEW_TOKEN }}" >> .github/workflows/ci.yml'
    case_ secrets-added-new-workflow        1 "adds a reference to secrets in .github/workflows/release.yml" 'printf "name: R\njobs:\n  r:\n    env:\n      K: \${{ secrets.K }}\n" > .github/workflows/release.yml'
    case_ secrets-inherit-added             1 "adds a reference to secrets" 'echo "    secrets: inherit" >> .github/workflows/ci.yml'
    case_ secrets-index-form-added          1 "adds a reference to secrets" 'echo "      - run: echo \${{ secrets[matrix.name] }}" >> .github/workflows/ci.yml'
    case_ secrets-added-after-a-plus                1 "adds a reference to secrets" 'echo "+\${{ secrets.X }}" >> .github/workflows/ci.yml'
    case_ secrets-bare-context-added                1 "adds a reference to secrets" 'echo "      - run: echo \${{ secrets }}" >> .github/workflows/ci.yml'
    case_ secrets-spaced-index-added                1 "adds a reference to secrets" 'echo "      - run: echo \${{ secrets [matrix.name] }}" >> .github/workflows/ci.yml'
    case_ secrets-upper-case-added                  1 "adds a reference to secrets" 'echo "      - run: echo \${{ SECRETS.X }}" >> .github/workflows/ci.yml'
    case_ other-workflow-change-passes      0 "" 'printf "  b:\n    steps:\n      - run: echo b\n" >> .github/workflows/ci.yml'
    case_ job-removal-passes                0 "" 'printf "name: CI\n" > .github/workflows/ci.yml'
    case_ secrets-removed-only-passes       0 "" 'printf "name: Old\njobs:\n  o:\n    env:\n      T: x\n" > .github/workflows/old.yml'
    case_ secrets-in-comment-passes         0 "" 'echo "# this job has no secrets.NAME" >> .github/workflows/ci.yml'
    case_ the-word-secrets-in-a-name-passes 0 "" 'echo "      - name: list my_secrets_dir" >> .github/workflows/ci.yml'
    case_ no-workflow-file-passes           0 "" 'echo more >> README.md'

    local out got
    out="$("$self" --repo "$r" --base no-such-ref 2>&1)"; got=$?
    if [ "$got" -eq 2 ]; then echo "ok   unknown base is an error (exit 2)"; else echo "FAIL unknown base: wanted exit 2, got $got: $out"; fails=$((fails + 1)); fi
    "$self" >/dev/null 2>&1; got=$?
    if [ "$got" -eq 2 ]; then echo "ok   no arguments is a usage error (exit 2)"; else echo "FAIL no arguments: wanted exit 2, got $got"; fails=$((fails + 1)); fi

    if [ "$fails" -eq 0 ]; then echo "check-workflow-guard self-test: all cases passed"; return 0; fi
    echo "check-workflow-guard self-test: $fails case(s) failed" >&2
    return 1
}

repo="."
base=""
head="HEAD"
mode=check
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) repo="${2:?--repo needs a directory}"; shift 2 ;;
        --base) base="${2:?--base needs a ref}"; shift 2 ;;
        --head) head="${2:?--head needs a ref}"; shift 2 ;;
        --self-test) mode=self-test; shift ;;
        *) usage ;;
    esac
done

if [ "$mode" = self-test ]; then self_test; exit $?; fi
[ -n "$base" ] || usage
guard "$repo" "$base" "$head"
