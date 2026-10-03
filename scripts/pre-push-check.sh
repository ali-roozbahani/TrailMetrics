#!/usr/bin/env bash
# Local quality gate — must pass before an agent (or a human) pushes a branch.
# Mirrors ci.yml's jobs so CI is a confirmation, not a discovery step.
#
# Exit codes: 0 = all required checks passed. Non-zero = do not push.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FAILURES=()
run_step() {
    local name="$1"; shift
    echo "==> $name"
    if ! "$@"; then
        FAILURES+=("$name")
        echo "!!  $name FAILED"
    fi
}

# --- Decide scope: did this branch touch iOS or shared/domain/data/core? ---
BASE_REF="$(git merge-base HEAD origin/main 2>/dev/null || echo "")"
if [ -z "$BASE_REF" ]; then
    echo "Warning: could not find merge-base with origin/main; checking all changes vs HEAD~1"
    BASE_REF="HEAD~1"
fi
CHANGED_FILES="$(git diff --name-only "$BASE_REF" HEAD 2>/dev/null || true)"

TOUCHES_IOS_OR_SHARED=false
if echo "$CHANGED_FILES" | grep -qE '^(iosApp/|domain/|data/|core/|shared/)'; then
    TOUCHES_IOS_OR_SHARED=true
fi

# --- Decide scope: may the heavy steps be skipped? ---
# scripts/classify-changes.sh decides it, the same script as CI. "light" (every changed file is
# on its non-source allowlist) skips the Android/KMP steps and the iOS steps; anything else,
# including a missing merge-base or an error from the script, is "full".
DECISION=full
if [ "$BASE_REF" = HEAD~1 ]; then
    CLASSIFICATION="$(printf 'full\n(no file list: no merge-base with origin/main)')"
else
    CLASSIFICATION="$(scripts/classify-changes.sh --base "$BASE_REF" 2>&1)"
    if [ $? -eq 0 ] && [ "${CLASSIFICATION%%$'\n'*}" = light ]; then
        DECISION=light
    fi
fi

echo "Changed files since $BASE_REF:"
echo "$CHANGED_FILES" | sed 's/^/  /'
echo "iOS/shared checks required: $TOUCHES_IOS_OR_SHARED"
echo

run_step "board check" scripts/check-board.sh

# Protected paths (.github/CODEOWNERS): the file must be valid and the classifier's own tests
# must pass. Same commands as CI's android job.
run_step "protected paths" bash -c 'scripts/check-protected-paths.sh --validate && scripts/check-protected-paths.sh --self-test'
run_step "change classification self-test" scripts/classify-changes.sh --self-test

# Report only: how the classifier sees this branch's diff. Never adds to FAILURES.
echo "==> protected-path classification of this branch (report only, never fails the gate)"
scripts/check-protected-paths.sh --base "$BASE_REF" 2>&1 | sed 's/^/    /' || true

# Report only: the change classification above and the files behind it. Never adds to FAILURES.
echo "==> change classification of this branch (report only, never fails the gate): $DECISION"
echo "$CLASSIFICATION" | tail -n +2 | sed 's/^/    /'
if [ "$DECISION" = light ]; then
    echo "    every changed file is on the non-source allowlist: Android/KMP and iOS steps skipped"
fi

# --- Android / KMP (unless the decision is light) ---
if [ "$DECISION" = full ]; then
    run_step "detekt"        ./gradlew detekt --console=plain
    run_step "android lint"  ./gradlew lint --console=plain
    run_step "unit tests"    ./gradlew allTests test --console=plain

    # Coverage report (Kover, merged across modules in the root project). Best-effort: never
    # added to FAILURES. The enforced part is the "coverage verify" step below.
    echo "==> coverage report (best-effort, non-blocking)"
    COVERAGE_OUT="$(mktemp 2>/dev/null || echo "")"
    if [ -n "$COVERAGE_OUT" ] \
        && ./gradlew :koverXmlReport :koverHtmlReport :koverLog --console=plain >"$COVERAGE_OUT" 2>&1; then
        COVERAGE_LINE="$(grep -m1 'line coverage:' "$COVERAGE_OUT" | sed 's/^.*line coverage: *//' || true)"
        echo "    merged line coverage: ${COVERAGE_LINE:-unknown}"
        echo "    report: $REPO_ROOT/build/reports/kover/html/index.html (XML: build/reports/kover/report.xml)"
    else
        echo "    warning: coverage report failed; continuing (does not affect the gate result)"
        [ -n "$COVERAGE_OUT" ] && tail -n 20 "$COVERAGE_OUT" | sed 's/^/    /'
    fi
    [ -n "$COVERAGE_OUT" ] && rm -f "$COVERAGE_OUT"

    # Regression gate: each module's koverVerify rules (minimum line coverage, set in domain, data
    # and the three androidApp feature modules; the other modules have no rules yet).
    run_step "coverage verify" ./gradlew koverVerify --console=plain

    run_step "assembleDebug" ./gradlew assembleDebug --console=plain
fi

# --- iOS (only when relevant files changed, and the decision is full) ---
if [ "$DECISION" = full ] && [ "$TOUCHES_IOS_OR_SHARED" = true ]; then
    if command -v swiftlint >/dev/null 2>&1; then
        run_step "swiftlint" bash -c 'cd iosApp && swiftlint lint --strict'
    else
        FAILURES+=("swiftlint (not installed — install with 'brew install swiftlint')")
    fi

    # Same hash-gated script as the Xcode scheme pre-action, so the iOS build and the package
    # tests below never link a stale XCFramework, whichever Xcode scheme is picked up.
    run_step "KMP XCFramework" scripts/build-kmp-framework.sh

    run_step "iOS build" bash -c '
        cd iosApp
        xcodebuild build \
            -project TrailMetrics.xcodeproj \
            -scheme TrailMetrics \
            -destination "generic/platform=iOS Simulator" \
            -skipMacroValidation \
            ARCHS=arm64 \
            EXCLUDED_ARCHS=x86_64 \
            ONLY_ACTIVE_ARCH=NO \
            CODE_SIGNING_ALLOWED=NO
    '

    # Runs after "iOS build": the packages link the XCFramework that build produces.
    # Every iosApp/Packages/<Name>/ with a Tests/ directory is tested; others are skipped.
    run_step "iOS package tests" bash -c '
        set -uo pipefail
        SIM_ID="$(xcrun simctl list devices available iPhone \
            | grep -oE "[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}" | tail -1)"
        if [ -z "$SIM_ID" ]; then
            echo "No available iPhone simulator (see LEARNINGS.md: xcodebuild -downloadPlatform iOS)"
            exit 1
        fi
        status=0
        for pkg in iosApp/Packages/*/; do
            name="$(basename "$pkg")"
            if [ ! -d "$pkg/Tests" ]; then
                echo "--- $name: no Tests/, skipped"
                continue
            fi
            echo "--- $name: xcodebuild test"
            (cd "$pkg" && xcodebuild test \
                -scheme "$name" \
                -destination "platform=iOS Simulator,id=$SIM_ID" \
                -skipMacroValidation \
                CODE_SIGNING_ALLOWED=NO) || status=1
        done
        exit $status
    '
fi

# --- Review verdict (soft: reports only) ---
# The pr-reviewer subagent's verdict, recorded by the session as one line `<full sha> <VERDICT>`
# (tm-pr-review skill), in the git dir like the pass marker below. This step never adds to
# FAILURES, never changes the exit code and never writes the pass marker.
report_review_verdict() {
    local head short file content sha
    head="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" || head=""
    short="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null)" || short="unknown"
    file="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path .review-verdict 2>/dev/null)" || file=""
    if [ -z "$file" ] || [ ! -e "$file" ]; then
        echo "no review verdict recorded for HEAD $short"
        return 0
    fi
    # A valid file is one short line; anything larger is malformed without reading it.
    if [ ! -f "$file" ] || [ "$(wc -c <"$file" 2>/dev/null | tr -d ' ')" -gt 100 ]; then
        echo "review verdict file is malformed"
        return 0
    fi
    content="$(LC_ALL=C tr -d '\000' <"$file" 2>/dev/null)" || content=""
    if [[ ! "$content" =~ ^([0-9a-f]{40}|[0-9a-f]{64})\ (APPROVE|CHANGES|ESCALATE_TO_HUMAN)$ ]]; then
        echo "review verdict file is malformed"
        return 0
    fi
    sha="${BASH_REMATCH[1]}"
    if [ -n "$head" ] && [ "$sha" = "$head" ]; then
        echo "review verdict for HEAD $short: ${BASH_REMATCH[2]}"
    else
        echo "no review verdict recorded for HEAD $short (last verdict was for ${sha:0:${#short}})"
    fi
    return 0
}
echo
echo "==> review verdict (report only, never fails the gate)"
report_review_verdict || true

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
    echo "All required checks passed. Safe to commit/push."
    # --git-path resolves to this checkout's own git dir: .git/ in the main checkout,
    # .git/worktrees/<name>/ in a linked worktree (where .git is a file, not a directory).
    # block-git-push.sh resolves the marker the same way.
    MARKER="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path .pre-push-check-passed)" \
        && touch "$MARKER" \
        || { echo "!!  could not write the pass marker; the push hook will block. Re-run once fixed."; exit 1; }
    exit 0
else
    echo "FAILED checks:"
    for f in "${FAILURES[@]}"; do echo "  - $f"; done
    echo
    echo "Do not push. Fix the above and re-run scripts/pre-push-check.sh."
    exit 1
fi
