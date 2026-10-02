#!/usr/bin/env bash
# Board check: BOARD.md's record format, Order/After, no line numbers, no dangling
# board `<slug>` mentions in the skills and docs. First step of pre-push-check.sh and CI.
#
#   scripts/check-board.sh              check (exit 0 = OK, 1 = problems found)
#   scripts/check-board.sh --next       print the record to take next
#   scripts/check-board.sh --self-test  run the fixtures in scripts/check-board-fixtures/
#
# The logic is in check-board.py (python3 standard library, present on macOS and ubuntu-latest).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "check-board: python3 not found" >&2
    exit 2
fi
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-board.py" "$@"
