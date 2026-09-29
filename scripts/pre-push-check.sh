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

echo "Changed files since $BASE_REF:"
echo "$CHANGED_FILES" | sed 's/^/  /'
echo "iOS/shared checks required: $TOUCHES_IOS_OR_SHARED"
echo

# --- Android / KMP (always) ---
run_step "detekt"        ./gradlew detekt --console=plain
run_step "android lint"  ./gradlew lint --console=plain
run_step "unit tests"    ./gradlew allTests test --console=plain
run_step "assembleDebug" ./gradlew assembleDebug --console=plain

# --- iOS (only when relevant files changed) ---
if [ "$TOUCHES_IOS_OR_SHARED" = true ]; then
    if command -v swiftlint >/dev/null 2>&1; then
        run_step "swiftlint" bash -c 'cd iosApp && swiftlint lint --strict'
    else
        FAILURES+=("swiftlint (not installed — install with 'brew install swiftlint')")
    fi

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
