#!/bin/bash
# Self-test of the SwiftLint custom rule `optional_try` (iosApp/.swiftlint.yml; tm-ios, "SwiftLint"),
# which bans an unannotated `try?` in iOS code. The rule runs in every `swiftlint lint --strict`
# (gate and CI's ios-main), but SwiftLint turns a custom rule OFF without failing when its
# `excluded_match_kinds` holds a name the installed version does not know: it only prints
# "Invalid configuration for 'optional_try' rule. Falling back to default." and reports no `try?`
# at all. This script runs the committed config against the fixtures in
# scripts/check-optional-try-fixtures/ and fails when the rule does not behave or SwiftLint prints
# that message:
#   violating/            3 unannotated `try?` (bare, bound with guard let, with await): 3 violations
#   annotated/            `// swiftlint:disable:next optional_try - <reason>` and do/catch: must pass
#   comments-and-strings/ `try?` in a line, block and doc comment, a string and a multiline string:
#                         must pass
# It also lints `violating/` with a copy of the config whose `excluded_match_kinds` has a name that
# does not exist, and expects exactly the silent failure above (no violation, the message printed),
# which proves the check for the message can see it.
#
#   scripts/check-optional-try.sh --self-test
#
# SWIFTLINT_CONFIG=<file> runs the cases against another config (to show them going red).
# Exit 0 when every case behaves, 1 when one does not, 2 for a usage error or no swiftlint.
# bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/scripts/check-optional-try-fixtures"
CONFIG="${SWIFTLINT_CONFIG:-$ROOT/iosApp/.swiftlint.yml}"
INVALID_MESSAGE="Invalid configuration for 'optional_try' rule"

if [ "${1:-}" != "--self-test" ] || [ $# -ne 1 ]; then
    echo "usage: scripts/check-optional-try.sh --self-test" >&2
    exit 2
fi
if ! command -v swiftlint >/dev/null 2>&1; then
    echo "swiftlint is not installed (brew install swiftlint)" >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# lint <case> <fixture dir> <config>: prints swiftlint's output (stdout and stderr)
lint() {
    local dir="$WORK/$1/iosApp/Fixture"
    mkdir -p "$dir"
    cp "$FIXTURES/$2"/*.swift "$dir/"
    (cd "$WORK/$1/iosApp" && swiftlint lint --strict --quiet --no-cache --config "$3" 2>&1)
}

count() { echo "$1" | grep -c "$2" || true; }

expect() { # <label> <actual> <expected>
    if [ "$2" = "$3" ]; then
        echo "ok   $1: $2"
    else
        echo "FAIL $1: expected $3, got $2"
        FAILED=1
    fi
}

for fixture in violating annotated comments-and-strings; do
    out="$(lint "$fixture" "$fixture" "$CONFIG")"
    if [ "$fixture" = violating ]; then want=3; else want=0; fi
    expect "$fixture: optional_try violations" "$(count "$out" '(optional_try)')" "$want"
    expect "$fixture: other errors" "$(count "$out" ' error: ' | awk -v n="$(count "$out" '(optional_try)')" '{print $1 - n}')" 0
    expect "$fixture: \"$INVALID_MESSAGE\" printed" "$(count "$out" "$INVALID_MESSAGE")" 0
done

# The silent failure: the same config with an excluded_match_kinds name SwiftLint does not know.
BROKEN="$WORK/broken.yml"
sed 's/^      - string$/      - not_a_syntax_kind/' "$CONFIG" > "$BROKEN"
if cmp -s "$CONFIG" "$BROKEN"; then
    echo "FAIL broken config: no 'excluded_match_kinds' entry '- string' found in $CONFIG to break"
    FAILED=1
else
    out="$(lint broken violating "$BROKEN")"
    expect "broken config: message printed" "$(count "$out" "$INVALID_MESSAGE")" 1
    expect "broken config: optional_try violations (rule silently off)" "$(count "$out" '(optional_try)')" 0
fi

[ "$FAILED" = 0 ] && echo "optional_try rule: self-test passed" || echo "optional_try rule: self-test FAILED"
exit "$FAILED"
