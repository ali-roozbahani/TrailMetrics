#!/usr/bin/env bash
# Fails when a tracked Kotlin file of production code calls `println(` or `print(`. detekt's
# ForbiddenMethodCall cannot see them: detekt 1.23.8 embeds Kotlin 2.0.21 and cannot resolve a call of a
# function that kotlin-stdlib 2.4 declares (config/detekt/detekt.yml, LEARNINGS.md). Text check, run by the
# gate and by CI's tooling job; tm-android, "Detekt", says why `println` is forbidden (use a logger).
#
#   scripts/check-no-println.sh              scan the tracked *.kt files of the checkout
#   scripts/check-no-println.sh --self-test  the cases below, on a throwaway git repository
#
# Production code is every tracked *.kt file outside a test source set (test, androidTest, commonTest,
# androidHostTest, iosTest, jvmTest, androidUnitTest, androidInstrumentedTest). A line that is only a
# comment is skipped; a call after a `.` (`System.out.println`, `logger.print`) is not this check's:
# only a bare call is. Exit 0 clean, 1 a hit (listed as file:line), 2 usage.
# bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIRS='/(test|androidTest|commonTest|androidHostTest|iosTest|jvmTest|androidUnitTest|androidInstrumentedTest)/'

scan() { # <repo dir>
    (cd "$1" && git ls-files -z '*.kt' | tr '\0' '\n' | grep -vE "$TEST_DIRS" |
        while IFS= read -r f; do
            grep -nE '(^|[^A-Za-z0-9_.])(println|print)\(' "$f" |
                grep -vE '^[0-9]+:[[:space:]]*(//|\*|/\*)' | sed "s#^#$f:#"
        done)
}

if [ "${1:-}" = "--self-test" ] && [ $# -eq 1 ]; then
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    cd "$WORK" && git init -q . && mkdir -p domain/src/commonMain app/src/main app/src/test
    printf 'fun a() { println("x") }\n' > domain/src/commonMain/Hit.kt
    printf 'fun a() { print(1) }\n' > app/src/main/Hit2.kt
    printf 'fun a() { println("x") }\n' > app/src/test/InTest.kt
    printf '// println("x")\n/** print(1) */\n * println(2)\nfun a() { System.out.println("x"); logger.print(1); myprint(2) }\n' > app/src/main/Clean.kt
    git add -A
    out="$(scan "$WORK")"
    failed=0
    for want in 'domain/src/commonMain/Hit.kt:1:' 'app/src/main/Hit2.kt:1:'; do
        echo "$out" | grep -q "^$want" && echo "ok   hit: $want" || { echo "FAIL missing: $want"; failed=1; }
    done
    n="$(echo "$out" | grep -c . || true)"
    [ "$n" = 2 ] && echo "ok   only the two production hits (a test file, comments and member calls are skipped)" || { echo "FAIL expected 2 hits, got $n:"; echo "$out"; failed=1; }
    [ "$failed" = 0 ] && echo "no-println check: self-test passed" || echo "no-println check: self-test FAILED"
    exit "$failed"
fi
if [ $# -ne 0 ]; then
    echo "usage: scripts/check-no-println.sh [--self-test]" >&2
    exit 2
fi

hits="$(scan "$ROOT")"
if [ -n "$hits" ]; then
    echo "println/print in production Kotlin (use a logger; tm-android, \"Detekt\"):"
    echo "$hits" | sed 's/^/  /'
    exit 1
fi
echo "no-println check: no println or print in production Kotlin"
