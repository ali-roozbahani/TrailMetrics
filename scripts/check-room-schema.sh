#!/usr/bin/env bash
# Room schema check: the exported schema files under data/schemas/ are append-only, the @Database
# version never goes down, a version bump comes with its schema file, its migration and a test that
# names it, and no main source set of data/ calls fallbackToDestructiveMigration. Compares HEAD with
# a base commit (committed trees only). The gate runs it against the merge base with origin/main,
# CI's android job against the PR's base commit. A second mode checks, after the build, that the
# build left data/schemas/ unchanged (schema export freshness).
#
#   scripts/check-room-schema.sh [--repo <dir>] --base <ref> [--head <ref>]
#                                                   compare <ref> with HEAD (or --head)
#   scripts/check-room-schema.sh [--repo <dir>] --check-export-fresh
#                                                   fail when data/schemas/ has a modified, deleted
#                                                   or untracked file in the working tree
#   scripts/check-room-schema.sh --self-test        run the fixtures in
#                                                   scripts/check-room-schema-fixtures/
#
# Exit 0 when the check passes (a report on stdout), 1 for a violation (messages on stderr), 2 for
# a usage or git error, which callers treat as a failure, never as a pass. The repository is the
# current directory unless --repo names another. The logic is in check-room-schema.py (python3
# standard library, present on macOS and ubuntu-latest).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "check-room-schema: python3 not found" >&2
    exit 2
fi
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-room-schema.py" "$@"
