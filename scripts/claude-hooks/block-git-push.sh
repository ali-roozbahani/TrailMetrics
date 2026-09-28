#!/usr/bin/env bash
# Claude Code PreToolUse hook. Fires before every Bash tool call; we only care
# about ones that look like `git push`. If the local gate hasn't been run and
# passed, block the push so the agent fixes things locally instead of pushing
# broken code and looping against GitHub CI.
#
# NOTE: wire-format for hook input/output (stdin JSON shape, exit-code
# semantics, matcher syntax) should be verified against the Claude Code docs
# current at setup time — hook mechanics have changed across versions. This
# script assumes: stdin is JSON with a `.tool_input.command` field, exit 0
# = allow, exit 2 = block and feed stderr back to the agent as the reason.

set -euo pipefail

INPUT="$(cat)"
COMMAND="$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"

# Only act on git push; let every other command through untouched.
if ! echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
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
