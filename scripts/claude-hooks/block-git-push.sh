#!/usr/bin/env bash
# Claude Code PreToolUse hook. Fires before every Bash tool call; we only care
# about ones that look like `git push`. If the local gate hasn't been run and
# passed, block the push so the agent fixes things locally instead of pushing
# broken code and looping against GitHub CI.
#
# Wire format verified 2026-09-28 against the Claude Code hooks reference
# (https://code.claude.com/docs/en/hooks): stdin is a JSON object with the
# shell command at `.tool_input.command`; exit 0 = no decision (normal
# permission flow), exit 2 = block, with stderr fed back to Claude as the reason.
# Registered in .claude/settings.json under PreToolUse with matcher "Bash".

set -euo pipefail

self_test() {
    local hook tmp fails=0 case_name want rc repo sha other
    hook="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' RETURN
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp"

    # mkrepo <name> <gh|other|none>: a repo with one commit and the given credential helper.
    mkrepo() {
        repo="$tmp/$1"
        git init -q "$repo"
        git -C "$repo" config user.email t@example.com
        git -C "$repo" config user.name t
        if [ "$2" = gh ]; then
            git -C "$repo" config --add credential.helper '!gh auth git-credential'
        elif [ "$2" = other ]; then
            git -C "$repo" config --add credential.helper osxkeychain
        fi
        git -C "$repo" commit -q --allow-empty -m init
        sha="$(git -C "$repo" rev-parse HEAD)"
        other="$(printf '%040d' 1)"
    }
    marker() { touch "$(git -C "$repo" rev-parse --path-format=absolute --git-path .pre-push-check-passed)"; }
    verdict() { printf '%s\n' "$1" > "$(git -C "$repo" rev-parse --path-format=absolute --git-path .review-verdict)"; }
    # expect <name> <want exit> <command>: run the hook in $repo and compare its own exit code.
    expect() {
        case_name="$1"; want="$2"
        rc=0
        (cd "$repo" && printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$3" "$repo" | bash "$hook" >/dev/null 2>&1) || rc=$?
        if [ "$rc" = "$want" ]; then
            echo "ok   $case_name (exit $rc)"
        else
            echo "FAIL $case_name: expected exit $want, got $rc" >&2
            fails=$((fails + 1))
        fi
    }

    mkrepo plain gh;          expect "non-push command passes" 0 "git status"
    mkrepo nohelper none;     marker; verdict "$sha APPROVE"; expect "no credential helper blocks" 2 "git push"
    mkrepo wronghelper other; marker; verdict "$sha APPROVE"; expect "wrong credential helper blocks" 2 "git push"
    mkrepo nomarker gh;       verdict "$sha APPROVE"; expect "no gate marker blocks" 2 "git push"
    mkrepo stale gh;          marker; sleep 1; git -C "$repo" commit -q --allow-empty -m next
    sha="$(git -C "$repo" rev-parse HEAD)"; verdict "$sha APPROVE"; expect "marker older than last commit blocks" 2 "git push"
    mkrepo norecord gh;       marker; expect "no verdict record blocks" 2 "git push"
    mkrepo otherrec gh;       marker; verdict "$other APPROVE"; expect "verdict for another SHA blocks" 2 "git push"
    mkrepo changes gh;        marker; verdict "$sha CHANGES"; expect "CHANGES blocks" 2 "git push"
    mkrepo malformed gh;      marker; verdict "$sha MAYBE"; expect "malformed record blocks" 2 "git push"
    mkrepo approve gh;        marker; verdict "$sha APPROVE"; expect "APPROVE passes" 0 "git push -u origin x"
    mkrepo escalate gh;       marker; verdict "$sha ESCALATE_TO_HUMAN"; expect "ESCALATE_TO_HUMAN passes" 0 "git -C . push"
    # The verdict is recorded before the gate's final run, so it is older than the marker.
    mkrepo order gh;          verdict "$sha APPROVE"; sleep 1; marker; expect "verdict older than marker passes" 0 "git push"

    if [ "$fails" -ne 0 ]; then
        echo "block-git-push.sh self-test: $fails failed" >&2
        return 1
    fi
    echo "block-git-push.sh self-test: all passed"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

INPUT="$(cat)"

# jq handles escaped quotes inside the command (e.g. `git commit -m \"x\" && git push`).
# Without jq, fall back to scanning the raw JSON: it may over-match, which blocks
# rather than lets a push through.
if command -v jq >/dev/null 2>&1 && COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"; then
    :
else
    COMMAND="$INPUT"
fi

# Only act on git push (including `git -C <dir> push`); let every other command through untouched.
if ! printf '%s\n' "$COMMAND" | grep -qE '(^|[^[:alnum:]_-])git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)*[[:space:]]+push([^[:alnum:]_-]|$)'; then
    exit 0
fi

# Check the checkout the push runs from (the session's cwd, which may be a linked
# worktree), not the one this script lives in. Fall back to this script's checkout
# when the cwd isn't inside a git work tree.
HOOK_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
REPO_ROOT="$(git -C "${HOOK_CWD:-$PWD}" rev-parse --show-toplevel 2>/dev/null \
    || { cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd; })"

# Pushes must authenticate with the machine token through `gh` only (tm-agent-loop section 5,
# Decision 1 of the agentic-dev-loop plan). git asks credential helpers in config order
# (system, global, local), and an empty value resets the list so far, so the keychain helper
# of the system config would otherwise answer first with the human's login. Compute the
# effective list the way git does and block unless it is exactly the gh helper. Only helper
# names from the config are read and printed, never a credential or an environment value.
GH_HELPER='!gh auth git-credential'
HELPERS=()
while IFS= read -r helper || [ -n "$helper" ]; do
    if [ -z "$helper" ]; then
        HELPERS=()
    else
        HELPERS+=("$helper")
    fi
done < <(git -C "$REPO_ROOT" config --get-all credential.helper 2>/dev/null || true)

if [ "${#HELPERS[@]}" -ne 1 ] || [ "${HELPERS[0]}" != "$GH_HELPER" ]; then
    {
        echo "Blocked: git could use a credential other than the machine token for this push."
        echo "The effective credential.helper list must be exactly one entry: $GH_HELPER"
        echo "Effective list (${#HELPERS[@]} entries):"
        for helper in "${HELPERS[@]+"${HELPERS[@]}"}"; do
            echo "  $helper"
        done
        echo "Fix, in this checkout: remove the local helper entries, then reset the inherited list and add gh:"
        echo "  git config --local --unset-all credential.helper"
        echo "  git config --local --add credential.helper ''"
        echo "  git config --local --add credential.helper '$GH_HELPER'"
    } >&2
    exit 2
fi

GATE_SCRIPT="$REPO_ROOT/scripts/pre-push-check.sh"
# Same resolution as pre-push-check.sh: .git/ in the main checkout,
# .git/worktrees/<name>/ in a linked worktree. Exit 2 on failure: exit 1 wouldn't block.
MARKER="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path .pre-push-check-passed 2>/dev/null)" || {
    echo "Blocked: could not locate the pre-push marker for $REPO_ROOT." >&2
    exit 2
}

# The gate script must have been run and passed since the last commit.
if [ ! -f "$MARKER" ]; then
    echo "Blocked: scripts/pre-push-check.sh has not been run yet. Run it, fix any failures, then push." >&2
    exit 2
fi

LAST_COMMIT_TIME="$(git -C "$REPO_ROOT" log -1 --format=%ct 2>/dev/null || echo 0)"
MARKER_TIME="$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER" 2>/dev/null || echo 0)"

if [ "$MARKER_TIME" -lt "$LAST_COMMIT_TIME" ]; then
    echo "Blocked: code changed since the last successful scripts/pre-push-check.sh run. Re-run it, then push." >&2
    exit 2
fi

# The local pr-reviewer verdict for HEAD must be recorded and be APPROVE or ESCALATE_TO_HUMAN
# (tm-pr-review, "Orchestrator's part"). Same file and format the gate reads
# (report_review_verdict in pre-push-check.sh): one line `<full sha> <VERDICT>` in the git dir.
# The session records it before the gate's final run, so this reads only that record and
# nothing the gate writes later.
VERDICT_FILE="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path .review-verdict 2>/dev/null)" || {
    echo "Blocked: could not locate the review verdict file for $REPO_ROOT." >&2
    exit 2
}
HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
VERDICT_CONTENT=""
# A valid file is one short line; anything larger is malformed without reading it.
if [ -f "$VERDICT_FILE" ] && [ "$(wc -c <"$VERDICT_FILE" 2>/dev/null | tr -d ' ')" -le 100 ]; then
    VERDICT_CONTENT="$(LC_ALL=C tr -d '\000' <"$VERDICT_FILE" 2>/dev/null || true)"
fi
if [[ "$VERDICT_CONTENT" =~ ^([0-9a-f]{40}|[0-9a-f]{64})\ (APPROVE|CHANGES|ESCALATE_TO_HUMAN)$ ]] \
    && [ -n "$HEAD_SHA" ] && [ "${BASH_REMATCH[1]}" = "$HEAD_SHA" ] \
    && [ "${BASH_REMATCH[2]}" != "CHANGES" ]; then
    exit 0
fi
{
    echo "Blocked: no local pr-reviewer verdict of APPROVE or ESCALATE_TO_HUMAN is recorded for HEAD ${HEAD_SHA:0:12}."
    echo "A missing or malformed record, a verdict for another commit, and CHANGES all block."
    echo "Run the reviewer and record its verdict (tm-pr-review, \"Orchestrator's part\"), then push."
} >&2
exit 2
