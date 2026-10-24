#!/usr/bin/env bash
# Claude Code PreToolUse hook. Fires before every Bash tool call; it acts only on a command that
# creates a branch or a worktree branch:
#   git switch -c/-C/--create/--force-create, git checkout -b/-B, git branch <name>,
#   git worktree add -b/-B (each also as `git -C <dir> ...`, and anywhere in a command chained
#   with && || ; |).
# For those it runs `scripts/prune-merged-branches.sh --check` in the session's cwd and blocks
# when a local branch whose PR is merged is left (exit 1 of the check) or the answer is unknown
# (exit 4, or anything else). Every other command passes untouched. The hook deletes nothing.
#
# Why: tm-pr-workflow, "Before starting", used to tell the agent in prose to delete the merged
# local branches, and three runs in a row created the next branch anyway.
#
# Wire format: same as block-git-push.sh (stdin JSON with the command at `.tool_input.command`
# and the session's directory at `.cwd`; exit 0 = no decision, exit 2 = block, stderr is fed back
# to Claude as the reason). Registered in .claude/settings.json under PreToolUse, matcher "Bash".
#
# Limits: this is a guardrail, not a wall. It reads the command text, so a branch created through
# a wrapper (`bash -c "git switch -c x"`) or a variable is not seen.
#
# BREAK-GLASS (human only): if this hook ever locks the agent out, remove its entry from
# .claude/settings.json (the PreToolUse hook that runs this file). There is deliberately no
# environment-variable or flag bypass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRUNE="$SCRIPT_DIR/../prune-merged-branches.sh"

# creates_branch <command text>: succeeds when some simple command in it creates a branch.
creates_branch() {
    local text="$1" segment word sub i
    local -a tokens
    # Split into simple commands at && || ; | & ( ) ` and newlines.
    while IFS= read -r segment; do
        read -ra tokens <<<"$segment" || true
        i=0
        # Leading VAR=value assignments.
        while [ "$i" -lt "${#tokens[@]}" ] && [[ "${tokens[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i + 1)); done
        [ "$i" -lt "${#tokens[@]}" ] || continue
        [ "${tokens[$i]##*/}" = git ] || continue
        i=$((i + 1))
        # git's own options: -C <dir> and -c <k=v> take an argument, any other -x is skipped.
        while [ "$i" -lt "${#tokens[@]}" ]; do
            case "${tokens[$i]}" in
                -C | -c) i=$((i + 2)) ;;
                -*) i=$((i + 1)) ;;
                *) break ;;
            esac
        done
        [ "$i" -lt "${#tokens[@]}" ] || continue
        sub="${tokens[$i]}"
        i=$((i + 1))
        case "$sub" in
            switch)
                for word in "${tokens[@]:$i}"; do
                    [ "$word" = -- ] && break
                    case "$word" in
                        --create | --create=* | --force-create | --force-create=*) return 0 ;;
                        --*) ;;
                        *) [[ "$word" =~ ^-[a-zA-Z]*[cC] ]] && return 0 ;;
                    esac
                done
                ;;
            checkout)
                for word in "${tokens[@]:$i}"; do
                    [ "$word" = -- ] && break
                    case "$word" in
                        --orphan | --orphan=*) return 0 ;;
                        --*) ;;
                        *) [[ "$word" =~ ^-[a-zA-Z]*[bB] ]] && return 0 ;;
                    esac
                done
                ;;
            worktree)
                [ "${tokens[$i]:-}" = add ] || continue
                for word in "${tokens[@]:$((i + 1))}"; do
                    [ "$word" = -- ] && break
                    case "$word" in
                        --orphan | --orphan=*) return 0 ;;
                        --*) ;;
                        *) [[ "$word" =~ ^-[a-zA-Z]*[bB] ]] && return 0 ;;
                    esac
                done
                ;;
            branch)
                # `git branch <name> [<start>]` creates; any option other than the ones that
                # modify a creation (-f -t -q --force --track --no-track --quiet) makes it a
                # listing, deletion, rename or similar.
                local positional=0 other_option=0
                for word in "${tokens[@]:$i}"; do
                    case "$word" in
                        -f | --force | -t | --track | --track=* | --no-track | -q | --quiet) ;;
                        -*) other_option=1 ;;
                        *) positional=1 ;;
                    esac
                done
                if [ "$positional" = 1 ] && [ "$other_option" = 0 ]; then return 0; fi
                ;;
        esac
    done < <(printf '%s\n' "$text" | tr '&|;()`' '\n\n\n\n\n\n')
    return 1
}

self_test() {
    local hook tmp fails=0 repo stub rc case_name want
    hook="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' RETURN
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp"

    # Stub `gh` as in prune-merged-branches.sh --self-test: one file per branch holds its PRs.
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
    git -C "$repo" branch old-merged
    git -C "$repo" branch open-b
    echo '[{"number":5,"state":"OPEN"}]' >"$tmp/prs/open-b"

    # expect <name> <want exit> <command>: run the hook in $repo and compare its own exit code.
    expect() {
        case_name="$1"; want="$2"
        rc=0
        (cd "$repo" && printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$3" "$repo" | bash "$hook" >/dev/null 2>"$tmp/err") || rc=$?
        if [ "$rc" = "$want" ]; then
            echo "ok   $case_name (exit $rc)"
        else
            echo "FAIL $case_name: expected exit $want, got $rc" >&2
            fails=$((fails + 1))
        fi
    }
    creating=(
        "git switch -c new-b"
        "git switch -C new-b"
        "git switch --create new-b"
        "git switch --force-create new-b"
        "git checkout -b new-b"
        "git checkout -B new-b"
        "git branch new-b"
        "git branch new-b main"
        "git worktree add -b new-b ../wt"
        "git worktree add ../wt -B new-b main"
        "git -C . switch -c new-b"
        "git -C . checkout -b new-b"
        "git -C . branch new-b"
        "git -C . worktree add -b new-b ../wt"
        "git fetch && git switch -c new-b origin/main"
    )
    others=(
        "git status"
        "ls"
        "git switch main"
        "git checkout main"
        "git checkout -- file.txt"
        "git branch"
        "git branch -vv"
        "git branch -D old-merged"
        "git branch --list chore/*"
        "git worktree add ../wt main"
        "git worktree list"
        "git commit -m fix"
        "echo git switch -c new-b"
    )

    # A merged branch is left: branch creation blocks, everything else passes.
    echo '[{"number":3,"state":"MERGED"}]' >"$tmp/prs/old-merged"
    for c in "${creating[@]}"; do expect "merged branch left blocks: $c" 2 "$c"; done
    for c in "${others[@]}"; do expect "merged branch left, passes: $c" 0 "$c"; done

    # The check cannot tell (gh fails): branch creation blocks, everything else passes.
    export STUB_GH_FAIL=1
    for c in "${creating[@]}"; do expect "unknown (exit 4) blocks: $c" 2 "$c"; done
    for c in "${others[@]}"; do expect "unknown, passes: $c" 0 "$c"; done
    unset STUB_GH_FAIL

    # Clean: nothing merged is left, branch creation passes.
    rm "$tmp/prs/old-merged"
    for c in "${creating[@]}"; do expect "clean check passes: $c" 0 "$c"; done

    # The reason names the way out.
    echo '[{"number":3,"state":"MERGED"}]' >"$tmp/prs/old-merged"
    expect "reason (merged)" 2 "git switch -c new-b"
    if grep -q 'scripts/prune-merged-branches.sh' "$tmp/err" && grep -q 'old-merged' "$tmp/err"; then
        echo "ok   reason says to run the script and names the branch"
    else
        echo "FAIL reason lacks the script or the branch" >&2
        fails=$((fails + 1))
    fi
    STUB_GH_FAIL=1 expect "reason (unknown)" 2 "git switch -c new-b"
    if grep -q 'do not bypass' "$tmp/err"; then
        echo "ok   unknown reason says to report and not bypass"
    else
        echo "FAIL unknown reason lacks the report instruction" >&2
        fails=$((fails + 1))
    fi

    if [ "$fails" -ne 0 ]; then
        echo "block-branch-create-while-merged-branches.sh self-test: $fails failed" >&2
        return 1
    fi
    echo "block-branch-create-while-merged-branches.sh self-test: all passed"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

INPUT="$(cat)"

# jq handles escaped quotes inside the command. Without jq, fall back to the raw JSON: that may
# over-match, which blocks rather than lets a branch creation through.
if command -v jq >/dev/null 2>&1 && COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"; then
    :
else
    COMMAND="$INPUT"
fi

creates_branch "$COMMAND" || exit 0

# Check the checkout the session works in (it may be a linked worktree), not the one this script
# lives in. Without a usable cwd the check runs in the directory the hook was started in.
HOOK_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"

RC=0
OUTPUT="$(cd "${HOOK_CWD:-$PWD}" 2>/dev/null && "$PRUNE" --check 2>&1)" || RC=$?

case "$RC" in
    0) exit 0 ;;
    1)
        {
            echo "Blocked: a local branch whose PR is merged is still here, so no new branch can be created yet."
            echo "$OUTPUT"
            echo "Run scripts/prune-merged-branches.sh (it deletes the merged ones and keeps open or PR-less branches), then create the branch."
            echo "Name the OPEN and NO_PR lines it prints in your report (tm-pr-workflow, \"Before starting\")."
        } >&2
        exit 2
        ;;
    *)
        {
            echo "Blocked: could not tell whether merged local branches are left (scripts/prune-merged-branches.sh --check exited $RC)."
            echo "$OUTPUT"
            echo "Report this to the human and stop; do not bypass the hook (no other route to a new branch)."
        } >&2
        exit 2
        ;;
esac
