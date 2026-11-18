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
# comment is skipped, and so is anything that is not a bare call: the text of a one-line string literal,
# a declaration (`fun print(`), and a call after a `.`. A member call (`System.out.println`, `logger.print`)
# and a qualified call (`kotlin.io.println(`) are not caught on purpose: the check is a text match for the
# bare call that `println("x")` is, and a call written with a dot is a deliberate choice that review sees.
# A multi-line (raw) string is not stripped: a line of one that holds `println(` is reported.
# Exit 0 clean, 1 a hit (listed as file:line), 2 usage.
# bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIRS='/(test|androidTest|commonTest|androidHostTest|iosTest|jvmTest|androidUnitTest|androidInstrumentedTest)/'

scan() { # <repo dir>
    (cd "$1" && git ls-files -z '*.kt' | tr '\0' '\n' | grep -vE "$TEST_DIRS" |
        while IFS= read -r f; do
            # one-line string literals and `fun print(` declarations are blanked first, line for line
            sed -E 's/"([^"\\]|\\.)*"/""/g; s/fun[[:space:]]+(println|print)\(/fun X(/g' "$f" |
                grep -nE '(^|[^A-Za-z0-9_.])(println|print)\(' |
                grep -vE '^[0-9]+:[[:space:]]*(//|\*|/\*)' | cut -d: -f1 |
                while IFS= read -r n; do echo "$f:$n:$(sed -n "${n}p" "$f")"; done
        done)
}

if [ "${1:-}" = "--self-test" ] && [ $# -eq 1 ]; then
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    cd "$WORK" && git init -q . && mkdir -p domain/src/commonMain app/src/main app/src/test
    printf 'fun a() { println("x") }\n' > domain/src/commonMain/Hit.kt
    printf 'fun a() { print(1) }\n' > app/src/main/Hit2.kt
    printf 'fun a() { println("x") }\n' > app/src/test/InTest.kt
    printf '// println("x")\n/** print(1) */\n * println(2)\nfun a() { System.out.println("x"); logger.print(1); myprint(2); kotlin.io.println(3) }\n' > app/src/main/Clean.kt
    printf 'class P { fun print(x: Int) {} }\nfun println(x: String) {}\n' > app/src/main/Declaration.kt
    printf 'val a = "call println(x) here"\nval b = "say \\"print(1)\\" twice"\nfun c() { val d = "x"; println("y") }\n' > app/src/main/Literal.kt
    git add -A
    out="$(scan "$WORK")"
    failed=0
    for want in 'domain/src/commonMain/Hit.kt:1:' 'app/src/main/Hit2.kt:1:' 'app/src/main/Literal.kt:3:'; do
        echo "$out" | grep -q "^$want" && echo "ok   hit: $want" || { echo "FAIL missing: $want"; failed=1; }
    done
    n="$(echo "$out" | grep -c . || true)"
    [ "$n" = 3 ] && echo "ok   only the three production hits (a test file, comments, member and qualified calls, a declaration and string literals are skipped)" || { echo "FAIL expected 3 hits, got $n:"; echo "$out"; failed=1; }
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
