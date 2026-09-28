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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE_SCRIPT="$REPO_ROOT/scripts/pre-push-check.sh"
MARKER="$REPO_ROOT/.git/.pre-push-check-passed"

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

exit 0
