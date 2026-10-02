#!/usr/bin/env bash
# Protected-path check: classifies a diff (or a list of files) as protected or unprotected,
# using .github/CODEOWNERS as the single source of truth for protected paths.
#
#   scripts/check-protected-paths.sh [--base <ref>]   files of `git diff <ref>...HEAD` (default origin/main)
#   scripts/check-protected-paths.sh --files <path>...  classify the given paths instead
#   scripts/check-protected-paths.sh --validate         check .github/CODEOWNERS itself
#   scripts/check-protected-paths.sh --self-test        run the built-in test cases
#
# Output (parsed by other tools, keep it stable): first line `protected` or `unprotected`,
# then one line per protected file as `<file>  (<pattern>)`. Exit 0 either way; exit 2 with a
# message on stderr for errors. The logic is in check-protected-paths.py (python3 standard
# library, present on macOS and ubuntu-latest).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "check-protected-paths: python3 not found" >&2
    exit 2
fi
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-protected-paths.py" "$@"
