#!/usr/bin/env bash
# Coverage floor ratchet: the Kover floors in config/kover-floors.properties may only go up. Compares
# the working tree's file with the same file on a base commit and fails when a floor is lower, when
# a module that reads the file has no entry, or when an entry has no module. The gate runs it against
# the merge base with origin/main, CI's android job against the PR's base commit.
#
#   scripts/check-kover-floors.sh [--repo <dir>] --base <ref>   compare the working tree with <ref>
#   scripts/check-kover-floors.sh --self-test                    run the fixtures in
#                                                                scripts/check-kover-floors-fixtures/
#
# Exit 0 when every floor is equal or higher (a report on stdout), 1 for a violation (messages on
# stderr), 2 for a usage or git error, which callers treat as a failure, never as a pass. The
# repository is the current directory unless --repo names another. The logic is in
# check-kover-floors.py (python3 standard library, present on macOS and ubuntu-latest).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "check-kover-floors: python3 not found" >&2
    exit 2
fi
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-kover-floors.py" "$@"
