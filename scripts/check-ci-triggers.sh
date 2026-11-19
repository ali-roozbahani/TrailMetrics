#!/usr/bin/env bash
# Policy check for the `push` triggers of .github/workflows/*.yml: a push trigger may name only branches that are
# never the head of a pull request (today `main`), because a push run and a pull_request run for the same head
# commit are two runs (their concurrency groups differ) and nothing dedupes them. Gate step; CI's `tooling`
# job runs its --self-test, which also checks the committed workflows, so CI enforces the rule without a step of
# its own in ci.yml. What it covers and what it does not: the header of check-ci-triggers.py.
#
#   scripts/check-ci-triggers.sh                    every workflow file of the checkout
#   scripts/check-ci-triggers.sh --file <path>...   these files
#   scripts/check-ci-triggers.sh --self-test        the fixtures in scripts/check-ci-triggers-fixtures/, then the
#                                                   committed workflows
#
# Exit: 0 clean, 1 a push trigger on a branch that can have a pull request (listed), 2 a workflow that cannot be
# read (a check that could not look is not a pass). The logic is in check-ci-triggers.py (python3 standard
# library, present on macOS and ubuntu-latest). Bash 3.2 compatible.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "check-ci-triggers: python3 not found" >&2
    exit 2
fi
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-ci-triggers.py" "$@"
