#!/bin/bash
# Self-test of the two SwiftLint custom rules that keep hardcoded user-visible strings out of iOS
# production code (iosApp/.swiftlint.yml: localized_text_without_bundle and
# literal_text_in_view_initializer; tm-ios, "Strings"). The rules themselves run in every
# `swiftlint lint --strict` (gate and CI's ios-main). This script runs the committed config
# against the fixtures in scripts/check-localized-strings-fixtures/ placed where the rules apply:
#   violating/     must fail: 2 localized_text_without_bundle and 5 literal_text_in_view_initializer
#   fixed/         the same view written the way tm-ios asks: must pass
#   out-of-scope/  literals in a Tests directory: must pass (the rules cover production sources only)
#
#   scripts/check-localized-strings.sh --self-test
#
# SWIFTLINT_CONFIG=<file> runs the cases against another config (to show them going red on one
# without the rules).
# Exit 0 when every case behaves, 1 when one does not, 2 for a usage error or no swiftlint.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/scripts/check-localized-strings-fixtures"
CONFIG="${SWIFTLINT_CONFIG:-$ROOT/iosApp/.swiftlint.yml}"

if [ "${1:-}" != "--self-test" ]; then
    echo "usage: scripts/check-localized-strings.sh --self-test" >&2
    exit 2
fi
if ! command -v swiftlint >/dev/null 2>&1; then
    echo "swiftlint is not installed (brew install swiftlint)" >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# lint <case> <relative dir in the fake iosApp> <fixture dir>: prints swiftlint's output
lint() {
    local dir="$WORK/$1/iosApp/$2"
    mkdir -p "$dir"
    cp "$FIXTURES/$3"/*.swift "$dir/"
    (cd "$WORK/$1/iosApp" && swiftlint lint --strict --quiet --no-cache --config "$CONFIG" 2>&1)
}

count() { echo "$1" | grep -c "($2)" || true; }

expect() { # <label> <actual> <expected>
    if [ "$2" = "$3" ]; then
        echo "ok   $1: $2"
    else
        echo "FAIL $1: expected $3, got $2"
        FAILED=1
    fi
}

out="$(lint violating Packages/Fixture/Sources/Fixture violating)"
expect "violating: localized_text_without_bundle" "$(count "$out" localized_text_without_bundle)" 2
expect "violating: literal_text_in_view_initializer" "$(count "$out" literal_text_in_view_initializer)" 5

out="$(lint app-target TrailMetrics violating)"
expect "violating in the app target: both rules fire" \
    "$(( $(count "$out" localized_text_without_bundle) + $(count "$out" literal_text_in_view_initializer) ))" 7

out="$(lint fixed Packages/Fixture/Sources/Fixture fixed)"
expect "fixed: violations" "$(echo "$out" | grep -c ' error: ' || true)" 0

out="$(lint out-of-scope Packages/Fixture/Tests/FixtureTests out-of-scope)"
expect "out-of-scope: violations" "$(echo "$out" | grep -c ' error: ' || true)" 0

out="$(lint ui-test-support TrailMetrics/UITestSupport out-of-scope)"
expect "app UITestSupport: violations" "$(echo "$out" | grep -c ' error: ' || true)" 0

[ "$FAILED" = 0 ] && echo "localized strings rules: self-test passed" || echo "localized strings rules: self-test FAILED"
exit "$FAILED"
