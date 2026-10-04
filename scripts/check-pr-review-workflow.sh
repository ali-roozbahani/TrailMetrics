#!/usr/bin/env bash
# Reviewer workflow self-test: runs the "Run pr-reviewer" and "Map verdict" scripts of
# .github/workflows/pr-review.yml, taken from the committed file, against a stub `claude` CLI,
# one scenario per fixture in scripts/check-pr-review-workflow-fixtures/. Gate and CI step.
#
#   scripts/check-pr-review-workflow.sh --self-test                    the committed workflow
#   scripts/check-pr-review-workflow.sh --self-test --workflow <file>  another copy of it
#
# The logic is in check-pr-review-workflow.py (python3 standard library, present on macOS and
# ubuntu-latest). The scripts under test need jq; without python3 or jq the self-test fails.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "check-pr-review-workflow: FAILED, python3 not found (needed to run the self-test)" >&2
    exit 2
fi
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-pr-review-workflow.py" "$@"
