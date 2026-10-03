#!/usr/bin/env bash
# Change classification: does a diff need the full CI and gate run, or only the board and
# protected-path checks? This script is the one place that decides it. CI's android and ios
# jobs call it with --github, scripts/pre-push-check.sh with --base.
#
#   scripts/classify-changes.sh --base <ref>       files of `git diff --no-renames <ref> HEAD`
#   scripts/classify-changes.sh --files <path>...  classify the given paths instead
#   scripts/classify-changes.sh --github           CI: `push` is always full; `pull_request`
#                                                  classifies the diff from PR_BASE_SHA (fetched
#                                                  if missing) to HEAD. Writes
#                                                  `decision=<light|full>` to $GITHUB_OUTPUT and
#                                                  the result to $GITHUB_STEP_SUMMARY.
#   scripts/classify-changes.sh --self-test        run the fixtures in scripts/classify-changes-fixtures/
#   --root <dir>   (first) run git in another repository (used by the fixtures)
#
# --base compares two trees (`<ref>` and HEAD), so <ref> is the merge-base (the gate) or the
# PR's base SHA (CI, where HEAD is the PR's merge commit). --no-renames lists both paths of a
# rename, so a source file renamed into docs/ still counts as source.
#
# Output (read by the callers, keep it stable): the first line is `light` or `full`. For
# `light`, one line per file as `<file>  (<allowlist entry>)`. For `full`, one line per file
# that made it full as `<file>  (not on the allowlist)`, or one line `(no file list: <reason>)`.
# Exit 0 for both; exit 2 for a usage error or a --github run that could not write its output
# (stdout still starts with `full`).
#
# Fail safe: `light` only when the file list was computed without an error, is not empty, and
# every file in it matches an allowlist entry. Anything else is `full`. Callers treat anything
# but exit 0 with a first line of exactly `light` as `full` too.
#
# Bash 3.2 (macOS /bin/bash) compatible; needs nothing but git.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# The non-source allowlist. Each entry has one of three forms, compared literally (no glob,
# no substring):
#   <dir>/**   every path that starts with `<dir>/`
#   *<suffix>  every path whose file name (after the last `/`) ends with <suffix>, at any depth
#   <path>     exactly that path
ALLOWLIST=(
    'docs/**'
    '*.md'
    'BOARD.md'
    '.claude/**'
    '.github/CODEOWNERS'
    '.github/workflows/pr-review.yml'
)

# Returns 0 when path $2 matches allowlist entry $1, 1 when it does not, 2 when the entry has
# none of the three forms.
entry_matches() {
    local entry="$1" path="$2" prefix suffix name
    case "$entry" in
        *'/**')
            prefix="${entry%'**'}"
            case "$prefix" in /* | *'*'* | *'?'* | *'['*) return 2 ;; esac
            [ "${#path}" -gt "${#prefix}" ] && [ "${path:0:${#prefix}}" = "$prefix" ]
            ;;
        '*'*)
            suffix="${entry#'*'}"
            case "$suffix" in '' | */* | *'*'* | *'?'* | *'['*) return 2 ;; esac
            name="${path##*/}"
            [ "${#name}" -ge "${#suffix}" ] && [ "${name:$((${#name} - ${#suffix}))}" = "$suffix" ]
            ;;
        '' | /* | *'*'* | *'?'* | *'['*)
            return 2
            ;;
        *)
            [ "$path" = "$entry" ]
            ;;
    esac
}

# Classifies the NUL-separated paths in file $1 and prints the result (format in the header).
classify_list() {
    local list="$1" path entry matched rc count=0 light_lines="" full_lines=""
    for entry in "${ALLOWLIST[@]}"; do
        entry_matches "$entry" "x"
        if [ $? -eq 2 ]; then
            printf 'full\n(no file list: allowlist entry %s has no supported form)\n' "$entry"
            return 0
        fi
    done
    while IFS= read -r -d '' path; do
        count=$((count + 1))
        matched=""
        for entry in "${ALLOWLIST[@]}"; do
            entry_matches "$entry" "$path"
            rc=$?
            if [ "$rc" -eq 0 ]; then
                matched="$entry"
                break
            fi
        done
        if [ -n "$matched" ]; then
            light_lines="$light_lines$path  ($matched)"$'\n'
        else
            full_lines="$full_lines$path  (not on the allowlist)"$'\n'
        fi
    done <"$list"
    if [ "$count" -eq 0 ]; then
        printf 'full\n(no file list: the list of changed files is empty)\n'
    elif [ -z "$full_lines" ]; then
        printf 'light\n%s' "$light_lines"
    else
        printf 'full\n%s' "$full_lines"
    fi
}

# Classifies `git diff --no-renames <base> HEAD` in $ROOT and prints the result.
classify_git() {
    local base="$1" tmp
    tmp="$(mktemp -d 2>/dev/null)" || { printf 'full\n(no file list: mktemp failed)\n'; return 0; }
    if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        printf 'full\n(no file list: %s is not a git repository)\n' "$ROOT"
    elif ! git -C "$ROOT" rev-parse --verify --quiet --end-of-options "HEAD^{commit}" >/dev/null 2>&1; then
        printf 'full\n(no file list: HEAD is not a commit)\n'
    elif ! git -C "$ROOT" rev-parse --verify --quiet --end-of-options "$base^{commit}" >/dev/null 2>&1; then
        printf 'full\n(no file list: base %s is not a commit here (missing, or shallow history))\n' "$base"
    elif ! git -C "$ROOT" diff --no-ext-diff --no-renames --name-only -z --end-of-options "$base" HEAD \
            >"$tmp/list" 2>"$tmp/err"; then
        printf 'full\n(no file list: git diff failed: %s)\n' "$(head -n 1 "$tmp/err")"
    else
        classify_list "$tmp/list"
    fi
    rm -rf "$tmp"
}

# Classifies the paths given as arguments and prints the result.
classify_files() {
    local tmp
    if [ $# -eq 0 ]; then
        printf 'full\n(no file list: no files given)\n'
        return 0
    fi
    tmp="$(mktemp 2>/dev/null)" || { printf 'full\n(no file list: mktemp failed)\n'; return 0; }
    printf '%s\0' "$@" >"$tmp"
    classify_list "$tmp"
    rm -f "$tmp"
}

# CI mode (see the header). EVENT_NAME and PR_BASE_SHA come from the workflow's env, never
# from interpolated event text.
github_mode() {
    local result decision=full event="${EVENT_NAME:-}" base="${PR_BASE_SHA:-}"
    case "$event" in
        pull_request)
            if [[ ! "$base" =~ ^[0-9a-f]{40}$ ]] && [[ ! "$base" =~ ^[0-9a-f]{64}$ ]]; then
                result=$'full\n(no file list: PR_BASE_SHA is not a commit SHA)'
            else
                if ! git -C "$ROOT" cat-file -e "$base^{commit}" 2>/dev/null; then
                    git -C "$ROOT" fetch --no-tags --quiet --depth=1 origin "$base" >&2 || true
                fi
                result="$(classify_git "$base")"
            fi
            ;;
        push)
            result=$'full\n(push event: always full)'
            ;;
        *)
            result="full"$'\n'"(event '$event': always full)"
            ;;
    esac
    [ "${result%%$'\n'*}" = "light" ] && decision=light
    printf '%s\n' "$result"
    if [ -z "${GITHUB_OUTPUT:-}" ] || ! printf 'decision=%s\n' "$decision" >>"$GITHUB_OUTPUT"; then
        echo "classify-changes: could not write to GITHUB_OUTPUT" >&2
        return 2
    fi
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            printf '### Change classification: %s\n\n' "$decision"
            if [ "$decision" = light ]; then
                printf 'Every changed file is on the non-source allowlist, so the heavy steps are skipped.\n\n'
            else
                printf 'All steps run.\n\n'
            fi
            printf '%s\n' "$result" | sed 's/^/    /'
        } >>"$GITHUB_STEP_SUMMARY" || true
    fi
    return 0
}

# --- Self-test -------------------------------------------------------------------------------
# Each directory in scripts/classify-changes-fixtures/ is one case:
#   changes  (optional) one change per line, fields separated by a tab: `A <path>`, `M <path>`,
#            `D <path>` or `R <old path> <new path>`. The case runs in a temporary git
#            repository with a base commit (holding every path that is modified, deleted or
#            renamed) and a head commit (the changes applied). No changes: head is empty.
#   expect   `args: ...` (default `--base {BASE}`), `env: NAME=VALUE`, `setup: shallow` (run in
#            a depth-1 clone that lacks the base) or `setup: no-repo` (run outside any git
#            repository), `exit: N` (default 0), `decision: light|full` (the first line of
#            stdout), `contains: text`, `absent: text`, `output: line` (a line of
#            $GITHUB_OUTPUT). `{BASE}` in args and env is the base commit's SHA.

fixture_git() {
    git -C "$1" -c user.name=classify-self-test -c user.email=self-test@example.invalid \
        -c commit.gpgsign=false -c core.hooksPath=/dev/null "${@:2}"
}

make_fixture_repo() {
    local repo="$1" changes="$2" op a b
    git init -q "$repo" || return 1
    echo seed >"$repo/seed.txt"
    if [ -f "$changes" ]; then
        while IFS=$'\t' read -r op a b || [ -n "$op" ]; do
            case "$op" in
                M | D | R) mkdir -p "$repo/$(dirname "$a")" && echo "base $a" >"$repo/$a" || return 1 ;;
            esac
        done <"$changes"
    fi
    fixture_git "$repo" add -A && fixture_git "$repo" commit -q -m base || return 1
    if [ -f "$changes" ]; then
        while IFS=$'\t' read -r op a b || [ -n "$op" ]; do
            case "$op" in
                A) mkdir -p "$repo/$(dirname "$a")" && echo "added $a" >"$repo/$a" ;;
                M) echo "changed" >>"$repo/$a" ;;
                D) fixture_git "$repo" rm -q -- "$a" ;;
                R) mkdir -p "$repo/$(dirname "$b")" && fixture_git "$repo" mv -- "$a" "$b" ;;
                '') ;;
                *) echo "unknown change '$op'" >&2; false ;;
            esac || return 1
        done <"$changes"
    fi
    fixture_git "$repo" add -A && fixture_git "$repo" commit -q --allow-empty -m head
}

run_fixture() {
    local dir="$1" entry="$2" name tmp repo root base line key value
    local args="--base {BASE}" setup="" want_exit=0 want_decision="" got_exit got_decision item
    local -a envs=() contains=() absent=() outputs=() errors=() argv=() envv=()
    name="$(basename "$dir")"
    while IFS= read -r line || [ -n "$line" ]; do
        key="${line%%: *}"
        value="${line#*: }"
        case "$key" in
            args) args="$value" ;;
            env) envs+=("$value") ;;
            setup) setup="$value" ;;
            exit) want_exit="$value" ;;
            decision) want_decision="$value" ;;
            contains) contains+=("$value") ;;
            absent) absent+=("$value") ;;
            output) outputs+=("$value") ;;
        esac
    done <"$dir/expect"

    tmp="$(mktemp -d)" || return 1
    repo="$tmp/repo"
    if ! make_fixture_repo "$repo" "$dir/changes" >"$tmp/setup.log" 2>&1; then
        echo "--- $name: SELF-TEST FAIL: could not build the fixture repository"
        sed 's/^/    /' "$tmp/setup.log"
        rm -rf "$tmp"
        return 1
    fi
    base="$(git -C "$repo" rev-parse HEAD~1)"
    root="$repo"
    case "$setup" in
        shallow)
            root="$tmp/shallow"
            git clone -q --depth 1 "file://$repo" "$root" 2>"$tmp/setup.log" || errors+=("could not clone")
            ;;
        no-repo)
            root="$tmp/no-repo"
            mkdir "$root"
            ;;
    esac

    read -r -a argv <<<"${args//\{BASE\}/$base}"
    for item in ${envs[@]+"${envs[@]}"}; do
        envv+=("${item//\{BASE\}/$base}")
    done
    : >"$tmp/github_output"
    (cd "$tmp" && env -u EVENT_NAME -u PR_BASE_SHA \
        GITHUB_OUTPUT="$tmp/github_output" GITHUB_STEP_SUMMARY="$tmp/summary" \
        GIT_CEILING_DIRECTORIES="$tmp" ${envv[@]+"${envv[@]}"} \
        bash "$entry" --root "$root" ${argv[@]+"${argv[@]}"}) >"$tmp/stdout" 2>"$tmp/stderr"
    got_exit=$?
    got_decision="$(head -n 1 "$tmp/stdout")"

    [ "$got_exit" = "$want_exit" ] || errors+=("exit $got_exit, expected $want_exit")
    [ -z "$want_decision" ] || [ "$got_decision" = "$want_decision" ] \
        || errors+=("decision '$got_decision', expected '$want_decision'")
    for item in ${contains[@]+"${contains[@]}"}; do
        cat "$tmp/stdout" "$tmp/stderr" | grep -Fq -- "$item" || errors+=("missing: $item")
    done
    for item in ${absent[@]+"${absent[@]}"}; do
        cat "$tmp/stdout" "$tmp/stderr" | grep -Fq -- "$item" && errors+=("unexpected: $item")
    done
    for item in ${outputs[@]+"${outputs[@]}"}; do
        grep -Fxq -- "$item" "$tmp/github_output" || errors+=("GITHUB_OUTPUT lacks: $item")
    done

    echo "--- $name (classify-changes.sh ${args}${setup:+, setup $setup}): exit $got_exit"
    cat "$tmp/stdout" "$tmp/stderr" | sed 's/^/    /'
    rm -rf "$tmp"
    if [ ${#errors[@]} -gt 0 ]; then
        for item in "${errors[@]}"; do echo "    SELF-TEST FAIL: $item"; done
        return 1
    fi
    return 0
}

self_test() {
    local fixtures="$SCRIPT_DIR/classify-changes-fixtures" entry="$SCRIPT_DIR/classify-changes.sh"
    local dir total=0 failed=0
    # The cases build their own repositories; nothing from the caller's git setup applies.
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    for dir in "$fixtures"/*/; do
        [ -f "$dir/expect" ] || continue
        total=$((total + 1))
        run_fixture "${dir%/}" "$entry" || failed=$((failed + 1))
    done
    echo "classify-changes self-test: $((total - failed))/$total fixtures passed"
    [ "$total" -gt 0 ] && [ "$failed" -eq 0 ]
}

# --- Entry point -----------------------------------------------------------------------------

usage_error() {
    printf 'full\n(no file list: usage error: %s)\n' "$1"
    echo "usage: classify-changes.sh [--root <dir>] (--base <ref> | --files <path>... | --github | --self-test)" >&2
    exit 2
}

main() {
    local mode="" base=""
    local -a files=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --root)
                [ $# -ge 2 ] || usage_error "--root needs a directory"
                ROOT="$2"
                shift 2
                ;;
            --base)
                [ $# -ge 2 ] && [ -n "$2" ] || usage_error "--base needs a ref"
                mode=base
                base="$2"
                shift 2
                ;;
            --files)
                mode=files
                shift
                [ $# -eq 0 ] || files=("$@")
                set --
                ;;
            --github | --self-test)
                mode="${1#--}"
                shift
                ;;
            *)
                usage_error "unknown argument '$1'"
                ;;
        esac
    done
    case "$mode" in
        base) classify_git "$base" ;;
        files) classify_files ${files[@]+"${files[@]}"} ;;
        github) github_mode ;;
        self-test) self_test ;;
        *) usage_error "no mode given" ;;
    esac
}

main "$@"
