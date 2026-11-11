#!/usr/bin/env bash
# Checks scripts/README.md, the index of the scripts: every `*.sh` and `*.py` file under scripts/
# (outside `*-fixtures/` folders) has exactly one index line, and every index line names a file
# that exists. An index line is a list item that starts with the script's path in backticks:
#   - `scripts/<path>`: <what it is for>
#
#   scripts/checks/scripts-index.sh --check       the repository this script is in
#   scripts/checks/scripts-index.sh --self-test   the cases in scripts/checks/scripts-index-fixtures/
#   --root <dir>   (first) another repository (used by the fixtures)
#
# Exit: 0 the index matches, 1 it does not (each problem on its own line), 2 usage error or no index.
# Bash 3.2 compatible.
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
USAGE="usage: scripts/checks/scripts-index.sh [--root <dir>] --check | --self-test"

check() {
    local index="$ROOT/scripts/README.md" listed problems=0 p n
    [ -f "$index" ] || { echo "scripts-index: no index at scripts/README.md" >&2; return 2; }
    listed="$(sed -n 's/^- `\(scripts\/[^`]*\)`:.*/\1/p' "$index")"
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        n="$(printf '%s\n' "$listed" | grep -cxF -- "$p")"
        if [ "$n" = 0 ]; then
            echo "$p has no line in scripts/README.md"; problems=$((problems + 1))
        elif [ "$n" -gt 1 ]; then
            echo "$p has $n lines in scripts/README.md"; problems=$((problems + 1))
        fi
    done < <(cd "$ROOT" && find scripts -type f \( -name '*.sh' -o -name '*.py' \) -not -path '*-fixtures/*' | LC_ALL=C sort)
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        [ -f "$ROOT/$p" ] || { echo "scripts/README.md names $p, which does not exist"; problems=$((problems + 1)); }
    done <<< "$listed"
    if [ "$problems" -ne 0 ]; then
        echo "scripts-index: FAILED, $problems problem(s)"
        return 1
    fi
    echo "scripts-index: OK, $(printf '%s\n' "$listed" | grep -c .) scripts indexed"
}

self_test() {
    local fixtures dir name expect_exit out code expect failed=0
    fixtures="$SELF_DIR/scripts-index-fixtures"
    for dir in "$fixtures"/*/; do
        [ -d "$dir" ] || { echo "FAIL no cases in $fixtures"; failed=1; break; }
        name="$(basename "$dir")"
        expect_exit="$(cat "$dir/expect-exit")"
        out="$(bash "$SELF_DIR/scripts-index.sh" --root "$dir/repo" --check 2>&1)"
        code=$?
        if [ "$code" != "$expect_exit" ]; then
            echo "FAIL $name: expected exit $expect_exit, got $code"; printf '%s\n' "$out" | sed 's/^/       /'; failed=1; continue
        fi
        while IFS= read -r expect || [ -n "$expect" ]; do
            [ -n "$expect" ] || continue
            if ! printf '%s\n' "$out" | grep -qF -- "$expect"; then
                echo "FAIL $name: output lacks '$expect'"; printf '%s\n' "$out" | sed 's/^/       /'; failed=1; continue 2
            fi
        done < "$dir/expect"
        echo "ok   $name (exit $code)"
    done
    bash "$SELF_DIR/scripts-index.sh" --bogus > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL a usage error does not exit 2"; failed=1; }
    if [ "$failed" = 0 ]; then echo "scripts-index: self-test passed"; else echo "scripts-index: self-test FAILED"; fi
    exit "$failed"
}

if [ "${1:-}" = "--self-test" ]; then
    [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }
    self_test
fi
if [ "${1:-}" = "--root" ]; then
    [ "$#" = 3 ] || { echo "$USAGE" >&2; exit 2; }
    ROOT="$(cd "$2" 2>/dev/null && pwd)" || { echo "scripts-index: no such directory: $2" >&2; exit 2; }
    shift 2
fi
[ "${1:-}" = "--check" ] && [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }
check
