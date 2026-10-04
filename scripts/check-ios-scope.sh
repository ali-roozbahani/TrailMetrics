#!/usr/bin/env bash
# iOS scope self-test: runs the block of scripts/pre-push-check.sh that decides whether the gate
# runs its iOS steps (between the markers `# >>> iOS scope: ... (begin) >>>` and
# `# <<< iOS scope: ... (end) <<<`), taken from the committed script, in scratch git
# repositories, one case per fixture in scripts/check-ios-scope-fixtures/. Gate and CI step.
#
#   scripts/check-ios-scope.sh --self-test                  the committed scripts/pre-push-check.sh
#   scripts/check-ios-scope.sh --self-test --script <file>  another copy of it
#
# The logic is in check-ios-scope.py (python3 standard library, present on macOS and
# ubuntu-latest). The block runs with the bash and git found on PATH; without python3, bash or
# git the self-test fails.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "check-ios-scope: FAILED, python3 not found (needed to run the self-test)" >&2
    exit 2
fi
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-ios-scope.py" "$@"
