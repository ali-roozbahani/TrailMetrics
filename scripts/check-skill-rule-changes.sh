#!/usr/bin/env bash
# Rule-weakening signal: lists every removed or rewritten line that holds a rule word, in any file
# under .claude/skills/ and in every file named CLAUDE.md, between two commits. Both reviewers get
# its output as the review input `rule-changes`, computed by the BASE branch's copy of this script
# (tm-pr-review, "Inputs"; .github/workflows/pr-review.yml, "Rule changes from the base").
#
#   scripts/check-skill-rule-changes.sh [--repo <dir>] <base> <head>   git diff <base> <head>
#   scripts/check-skill-rule-changes.sh --self-test                     run the fixtures in
#                                                                       scripts/check-skill-rule-changes-fixtures/
#
# Output (parsed by the reviewers, keep it stable): the single line `none`, or one line per listed
# item as `<file>:<line on the base side>: <removed text>`. Exit 0 in both cases; exit 2 with a
# message on stderr for a usage or git error, which callers treat as a failure, never as `none`.
# The repository is the current directory unless --repo names another. The logic is in
# check-skill-rule-changes.py (python3 standard library, present on macOS and ubuntu-latest).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "check-skill-rule-changes: python3 not found" >&2
    exit 2
fi
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-skill-rule-changes.py" "$@"
