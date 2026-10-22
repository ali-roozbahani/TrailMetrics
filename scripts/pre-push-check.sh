#!/usr/bin/env bash
# Local quality gate — must pass before an agent (or a human) pushes a branch.
# Mirrors ci.yml's jobs so CI is a confirmation, not a discovery step.
#
# Exit codes: 0 = all required checks passed. Non-zero = do not push.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Remove secret-looking variables (deny list in scripts/scrub-env.sh) from the gate's own
# environment before any step runs: xcodebuild logs the environment of the framework script's
# pre-action and Run Script phase, and no step needs a token. Fail closed: if the file cannot be
# sourced or a matching variable cannot be removed, the gate stops.
if ! source "$REPO_ROOT/scripts/scrub-env.sh" || ! scrub_secret_env; then
    echo "!!  could not remove secret-looking variables from the environment (scripts/scrub-env.sh)"
    echo "Gate stopped before any step. Do not push."
    exit 1
fi

FAILURES=()
run_step() {
    local name="$1"; shift
    echo "==> $name"
    if ! "$@"; then
        FAILURES+=("$name")
        echo "!!  $name FAILED"
    fi
}

# >>> iOS scope: BASE_REF, CHANGED_FILES, TOUCHES_IOS_OR_SHARED, TOUCHES_IOS_UI (begin) >>>
# --- Decide scope: did this branch touch iOS, shared/domain/data/core or the framework's build? ---
# The iOS steps run for a changed file under iosApp/, domain/, data/, core/, shared/ or
# shared-uitest/ (the test-only variant of the framework, ADR-002) that is not markdown, for the
# root Gradle files that configure the shared framework's build, for the Gradle
# wrapper and daemon JVM files that run it (gradlew, gradle/wrapper/gradle-wrapper.jar and
# .properties, gradle/gradle-daemon-jvm.properties) and for scripts/build-kmp-framework.sh, the
# iOS steps' own framework build. Not for gradlew.bat (Windows only, nothing here runs it),
# this script (CI's macOS iOS jobs run in full for it) or scripts/check-variant-api.sh (only
# `--variant uitest` runs it; deliberately NOT part of the UI scope below, and its self-test
# runs in every gate run). Exact paths and an exact `.md` suffix, as in scripts/classify-changes.sh:
# `data/README.md.kt` counts, `androidApp/app/build.gradle.kts` does not.
IOS_PATHS='^(iosApp/|domain/|data/|core/|shared/|shared-uitest/)|^(build\.gradle\.kts|settings\.gradle\.kts|gradle\.properties|gradle/libs\.versions\.toml|gradle/wrapper/gradle-wrapper\.properties|gradle/wrapper/gradle-wrapper\.jar|gradle/gradle-daemon-jvm\.properties|gradlew|scripts/build-kmp-framework\.sh)$'
IOS_PATHS_EXCLUDED='\.md$'
# TOUCHES_IOS_UI (the smoke UI test step) is a narrower question: did the branch touch what the
# UI tests drive or are built from (the app target, the UI-test target, a package's Sources/, the
# shared framework's commonMain and iosMain, the test-only variant)? Same exclusion of markdown.
# Not domain/, data/ or core/ on their own, and not scripts/check-variant-api.sh, which is
# deliberately outside this scope (its self-test runs in every gate run).
IOS_UI_PATHS='^(iosApp/TrailMetrics/|iosApp/TrailMetricsUITests/|iosApp/Packages/[^/]+/Sources/|shared/src/(commonMain|iosMain)/|shared-uitest/)'
# The list is `git diff --no-renames -z`, as in scripts/classify-changes.sh: a move lists both
# its paths, and no path is quoted (non-ASCII) or split (a newline in a name). Each path is
# matched as one string with bash's =~, never line by line. Fail-safe: when the branch's list
# cannot be read exactly (no merge-base with origin/main, so the HEAD~1 fallback is not this
# branch's diff; git diff fails; no temp dir), TOUCHES_IOS_OR_SHARED is true and a warning says
# why, with the first line of git's error. An empty list read without an error stays false.
IOS_SCOPE_NL=$'\n'
IOS_SCOPE_PROBLEM=""
IOS_SCOPE_TMP="$(mktemp -d 2>/dev/null)" || IOS_SCOPE_TMP=""
IOS_SCOPE_ERR=/dev/null
[ -n "$IOS_SCOPE_TMP" ] && IOS_SCOPE_ERR="$IOS_SCOPE_TMP/err"
BASE_REF="$(git merge-base HEAD origin/main 2>"$IOS_SCOPE_ERR")" || BASE_REF=""
if [ -z "$BASE_REF" ]; then
    echo "Warning: could not find merge-base with origin/main; checking all changes vs HEAD~1"
    IOS_SCOPE_GIT_ERR="$(head -n 1 "$IOS_SCOPE_ERR" 2>/dev/null)"
    IOS_SCOPE_PROBLEM="no merge-base with origin/main (${IOS_SCOPE_GIT_ERR:-no common ancestor}), so the HEAD~1 list is not this branch's diff"
    BASE_REF="HEAD~1"
fi
CHANGED_FILES=""
TOUCHES_IOS_OR_SHARED=false
TOUCHES_IOS_UI=false
if [ -z "$IOS_SCOPE_TMP" ]; then
    IOS_SCOPE_PROBLEM="${IOS_SCOPE_PROBLEM:+$IOS_SCOPE_PROBLEM; }mktemp failed, so no file list"
elif ! git diff --no-ext-diff --no-renames --name-only -z --end-of-options "$BASE_REF" HEAD \
        >"$IOS_SCOPE_TMP/list" 2>"$IOS_SCOPE_ERR"; then
    IOS_SCOPE_GIT_ERR="$(head -n 1 "$IOS_SCOPE_ERR" 2>/dev/null)"
    IOS_SCOPE_PROBLEM="${IOS_SCOPE_PROBLEM:+$IOS_SCOPE_PROBLEM; }git diff $BASE_REF HEAD failed: ${IOS_SCOPE_GIT_ERR:-no error message}"
else
    while IFS= read -r -d '' IOS_SCOPE_PATH; do
        CHANGED_FILES="${CHANGED_FILES:+$CHANGED_FILES$IOS_SCOPE_NL}$IOS_SCOPE_PATH"
        if [[ "$IOS_SCOPE_PATH" =~ $IOS_PATHS ]] && [[ ! "$IOS_SCOPE_PATH" =~ $IOS_PATHS_EXCLUDED ]]; then
            TOUCHES_IOS_OR_SHARED=true
        fi
        if [[ "$IOS_SCOPE_PATH" =~ $IOS_UI_PATHS ]] && [[ ! "$IOS_SCOPE_PATH" =~ $IOS_PATHS_EXCLUDED ]]; then
            TOUCHES_IOS_UI=true
        fi
    done <"$IOS_SCOPE_TMP/list"
fi
[ -n "$IOS_SCOPE_TMP" ] && rm -rf "$IOS_SCOPE_TMP"
if [ -n "$IOS_SCOPE_PROBLEM" ]; then
    TOUCHES_IOS_OR_SHARED=true
    TOUCHES_IOS_UI=true
    echo "Warning: the changed-file list for the iOS scope is not exact: $IOS_SCOPE_PROBLEM"
    echo "         iOS/shared checks required: true (fail-safe)"
fi
# <<< iOS scope: BASE_REF, CHANGED_FILES, TOUCHES_IOS_OR_SHARED, TOUCHES_IOS_UI (end) <<<

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

# One flag for both the secrets config check and the iOS steps below, so the iOS steps never run
# without that check having run first.
RUN_IOS_STEPS=false
if [ "$DECISION" = full ] && [ "$TOUCHES_IOS_OR_SHARED" = true ]; then
    RUN_IOS_STEPS=true
fi

echo "Changed files since $BASE_REF:"
echo "$CHANGED_FILES" | sed 's/^/  /'
echo "iOS/shared checks required: $TOUCHES_IOS_OR_SHARED"
echo "iOS UI smoke test required: $TOUCHES_IOS_UI"
echo

run_step "board check" scripts/check-board.sh

# Protected paths (.github/CODEOWNERS): the file must be valid and the classifier's own tests
# must pass. Same commands as CI's android job.
run_step "protected paths" bash -c 'scripts/check-protected-paths.sh --validate && scripts/check-protected-paths.sh --self-test'
run_step "change classification self-test" scripts/classify-changes.sh --self-test
run_step "reviewer workflow self-test" scripts/check-pr-review-workflow.sh --self-test
run_step "skill rule-change self-test" scripts/check-skill-rule-changes.sh --self-test
run_step "kover floors self-test" scripts/check-kover-floors.sh --self-test
run_step "room schema self-test" scripts/check-room-schema.sh --self-test
run_step "iOS scope self-test" scripts/check-ios-scope.sh --self-test
run_step "variant API check self-test" scripts/check-variant-api.sh --self-test
run_step "production framework check self-test" scripts/check-production-framework.sh --self-test
run_step "scrub-env self-test" scripts/scrub-env.sh --self-test
run_step "xcode log filter self-test" scripts/filter-xcode-log.sh --self-test
run_step "CI verdict reader self-test" scripts/read-ci-verdict.sh --self-test
run_step "board check self-test" scripts/check-board.sh --self-test
run_step "push hook self-test" scripts/claude-hooks/block-git-push.sh --self-test
run_step "skill changes digest self-test" scripts/skill-changes-digest.sh --self-test

# Coverage floors (config/kover-floors.properties) only go up: compared with the merge base, in
# every classification, light included (no Gradle needed). Same check as CI's android job, which
# compares with the PR's base commit. Fail closed: a missing or non-executable script, or no
# merge-base with origin/main (BASE_REF fell back to HEAD~1, which is not this branch's base),
# fails the step.
check_kover_floors() {
    local script="$REPO_ROOT/scripts/check-kover-floors.sh"
    if [ ! -f "$script" ] || [ ! -x "$script" ]; then
        echo "scripts/check-kover-floors.sh is missing or not executable"
        return 1
    fi
    if [ "$BASE_REF" = HEAD~1 ]; then
        echo "no merge-base with origin/main: nothing to compare the floors with"
        return 1
    fi
    "$script" --base "$BASE_REF"
}
run_step "kover floors" check_kover_floors

# Room schema (Decision 4 of docs/epics/protected-paths-review-2.md): exported schema files are
# append-only, a version bump has its schema file, migration and test, no destructive fallback.
# Compared with the merge base, in every classification, light included (no Gradle needed). Same
# check as CI's android job, which compares with the PR's base commit. Fail closed as above.
check_room_schema() {
    local script="$REPO_ROOT/scripts/check-room-schema.sh"
    if [ ! -f "$script" ] || [ ! -x "$script" ]; then
        echo "scripts/check-room-schema.sh is missing or not executable"
        return 1
    fi
    if [ "$BASE_REF" = HEAD~1 ]; then
        echo "no merge-base with origin/main: nothing to compare the Room schema with"
        return 1
    fi
    "$script" --base "$BASE_REF"
}
run_step "room schema" check_room_schema

# Report only: how the classifier sees this branch's diff. Never adds to FAILURES.
echo "==> protected-path classification of this branch (report only, never fails the gate)"
scripts/check-protected-paths.sh --base "$BASE_REF" 2>&1 | sed 's/^/    /' || true

# Report only: the change classification above and the files behind it. Never adds to FAILURES.
echo "==> change classification of this branch (report only, never fails the gate): $DECISION"
echo "$CLASSIFICATION" | tail -n +2 | sed 's/^/    /'
if [ "$DECISION" = light ]; then
    echo "    every changed file is on the non-source allowlist: Android/KMP and iOS steps skipped"
fi

# --- iOS secrets config (only when the iOS steps will run; before any long step) ---
# The iOS build needs this git-ignored file (README "iOS", step 2; CI writes a placeholder).
# Without it xcodebuild fails at settings resolution (LEARNINGS.md, item 4), about 15 minutes
# into the gate. It holds a Maps key: this is an existence test only, the file is never read,
# sourced or printed, and the gate never creates it. Fail-safe: anything that makes the test
# false (no file, a directory, an unreadable parent directory) stops the gate; nothing here can
# skip the iOS steps.
IOS_SECRETS_CONFIG="iosApp/TrailMetrics/Secrets.xcconfig"
if [ "$RUN_IOS_STEPS" = true ] && [ ! -f "$REPO_ROOT/$IOS_SECRETS_CONFIG" ]; then
    echo "!!  iOS secrets config missing: $IOS_SECRETS_CONFIG"
    echo "    This branch's changes need the iOS steps, and the iOS build cannot start without"
    echo "    this git-ignored file. Create it as README.md, \"Setup\" > \"iOS\", step 2 describes,"
    echo "    in this checkout (a new clone or worktree does not have it). Never commit it."
    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo "    Also failed before this check:"
        for f in "${FAILURES[@]}"; do echo "      - $f"; done
    fi
    echo
    echo "Gate stopped before the long steps. Do not push."
    exit 1
fi

# --- Android / KMP (unless the decision is light) ---
if [ "$DECISION" = full ]; then
    # Clear Room's schema build output before the first Gradle step (lint, the tests and
    # assembleDebug all run :data:copyRoomSchemas). Room writes it only when the schema differs
    # from the committed one, so an entity change that was built and then reverted leaves a stale
    # file that copyRoomSchemas would copy back over data/schemas/, a false red in "room schema
    # export fresh". Without it the KSP tasks run again (about 2 seconds on a warm build) and write
    # it only for a real difference; copyRoomSchemas finds no source and leaves data/schemas/ alone.
    rm -rf "$REPO_ROOT/data/build/intermediates/room/schemas"

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

    # Regression gate: each module's koverVerify rules (minimum line coverage in domain, data and
    # the three androidApp feature modules, values in config/kover-floors.properties; the other
    # modules have no rules yet).
    run_step "coverage verify" ./gradlew koverVerify --console=plain

    run_step "assembleDebug" ./gradlew assembleDebug --console=plain

    # Schema export freshness: the build must leave data/schemas/ as committed. Room's KSP step
    # rewrites the current version's schema file when an entity changed without a version bump,
    # and adds a file for a new version. A converter that keeps its column type does not change
    # the exported schema, so this step does not see it (the migration harness and tm-pr-review
    # item 12 do). Only after the Gradle build ran.
    run_step "room schema export fresh" scripts/check-room-schema.sh --check-export-fresh
fi

# --- iOS (only when relevant files changed, and the decision is full) ---
if [ "$RUN_IOS_STEPS" = true ]; then
    if command -v swiftlint >/dev/null 2>&1; then
        run_step "swiftlint" bash -c 'cd iosApp && swiftlint lint --strict'
    else
        FAILURES+=("swiftlint (not installed — install with 'brew install swiftlint')")
    fi

    # The two SwiftLint rules that keep hardcoded user-visible strings out of iOS code, run against
    # their fixtures (violating, fixed, out of scope). Needs swiftlint, like the step above.
    if command -v swiftlint >/dev/null 2>&1; then
        run_step "localized strings rules self-test" scripts/check-localized-strings.sh --self-test
    fi

    # Same hash-gated script as the Xcode scheme pre-action, so the iOS build and the package
    # tests below never link a stale XCFramework, whichever Xcode scheme is picked up.
    run_step "KMP XCFramework" scripts/build-kmp-framework.sh

    # No test-only Kotlin (the Swift test support of :shared-uitest) in the production framework
    # that was just built; the same check runs in CI's ios-main job.
    run_step "production framework check" scripts/check-production-framework.sh

    # Both xcodebuild steps print their output (stderr too) through scripts/filter-xcode-log.sh,
    # which drops Xcode's dumps of the build settings it passes to script phases (`export NAME\=value`
    # lines, a Maps key among them). pipefail keeps xcodebuild's failure. Fail closed: without an
    # executable filter the step fails before xcodebuild starts, so nothing unfiltered is printed.
    run_step "iOS build" bash -c '
        set -o pipefail
        filter="$PWD/scripts/filter-xcode-log.sh"
        if [ ! -f "$filter" ] || [ ! -x "$filter" ]; then
            echo "scripts/filter-xcode-log.sh is missing or not executable: xcodebuild not run"
            exit 1
        fi
        cd iosApp
        xcodebuild build \
            -project TrailMetrics.xcodeproj \
            -scheme TrailMetrics \
            -destination "generic/platform=iOS Simulator" \
            -skipMacroValidation \
            ARCHS=arm64 \
            EXCLUDED_ARCHS=x86_64 \
            ONLY_ACTIVE_ARCH=NO \
            CODE_SIGNING_ALLOWED=NO 2>&1 | "$filter"
    '

    # The Swift package tests use the Kotlin test support (SwiftTestFlow and the rest), which only
    # the test-only variant of the framework holds (:shared-uitest, ADR-002 "Amendment"). So the
    # variant is built here, the way CI's ios-main job builds it, and the packages link it. The
    # normal build after it rebuilds production (the stamp records the variant).
    run_step "KMP XCFramework (test-only variant)" scripts/build-kmp-framework.sh --variant uitest

    # Runs after "iOS build" and the variant build: the packages link the XCFramework at the debug
    # path, which holds the test-only variant now.
    # Every iosApp/Packages/<Name>/ with a Tests/ directory is tested; others are skipped.
    run_step "iOS package tests" bash -c '
        set -uo pipefail
        filter="$PWD/scripts/filter-xcode-log.sh"
        if [ ! -f "$filter" ] || [ ! -x "$filter" ]; then
            echo "scripts/filter-xcode-log.sh is missing or not executable: xcodebuild not run"
            exit 1
        fi
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
                CODE_SIGNING_ALLOWED=NO 2>&1 | "$filter") || status=1
        done
        exit $status
    '

    # The smoke UI test: one XCUITest (DetailsFailedDeleteUITests, the failed-delete scenario of
    # docs/epics/ios-ui-tests.md D4), only when the branch touches the UI scope
    # (TOUCHES_IOS_UI). CI builds the variant once in `ios-build-ui` and runs all UI tests in
    # `ios-ui`. Last in the iOS part: `--variant uitest` leaves the test-only framework at the debug
    # path, and a normal build after it rebuilds the production one. Same simulator selection and
    # the same flags as CI; the output goes through scripts/filter-xcode-log.sh (the local
    # secrets config holds a real Maps key). No retries: red is red (D6).
    #
    # Hard limit of IOS_SMOKE_LIMIT seconds for the whole step (variant build, app build, test).
    # macOS has no `timeout`, so a small perl wrapper runs the step in its own process group and
    # kills the group (xcodebuild, Gradle, the simulator's test runner) when the alarm fires; exit
    # code 124 then means the limit was hit. Ctrl-C (INT), TERM and HUP reach only the gate's own
    # group, so the wrapper catches them and kills the step's group the same way (exit 130, 143,
    # 129); signals are blocked until the child's pid is known. xcodebuild's own per-test allowance (90 s) comes
    # first when only the test hangs and names the test in the log.
    IOS_SMOKE_LIMIT=180
    IOS_SMOKE_TEST='TrailMetricsUITests/DetailsFailedDeleteUITests/test_failedDelete_showsErrorAndKeepsDetails'
    ios_smoke_ui_test() {
        local started=$SECONDS status
        perl -e '
            use POSIX qw(sigprocmask SIG_BLOCK SIG_UNBLOCK SIGINT SIGTERM SIGHUP SIGALRM);
            my $limit = shift;
            my $pid = 0;
            my $stop = sub {
                $SIG{$_} = "IGNORE" for qw(INT TERM HUP ALRM);
                if ($pid) { kill "TERM", -$pid; sleep 3; kill "KILL", -$pid; waitpid($pid, 0); }
                exit shift;
            };
            $SIG{ALRM} = sub { $stop->(124) };
            $SIG{INT} = sub { $stop->(130) };
            $SIG{TERM} = sub { $stop->(143) };
            $SIG{HUP} = sub { $stop->(129) };
            my $signals = POSIX::SigSet->new(SIGINT, SIGTERM, SIGHUP, SIGALRM);
            sigprocmask(SIG_BLOCK, $signals);
            $pid = fork();
            die "fork failed: $!" unless defined $pid;
            if (!$pid) {
                $SIG{$_} = "DEFAULT" for qw(INT TERM HUP ALRM);
                sigprocmask(SIG_UNBLOCK, $signals);
                setpgrp(0, 0);
                exec @ARGV;
                exit 127;
            }
            alarm $limit;
            sigprocmask(SIG_UNBLOCK, $signals);
            waitpid($pid, 0);
            my $status = $?;
            $pid = 0;
            exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
        ' "$IOS_SMOKE_LIMIT" bash -c '
            set -o pipefail
            filter="$PWD/scripts/filter-xcode-log.sh"
            if [ ! -f "$filter" ] || [ ! -x "$filter" ]; then
                echo "scripts/filter-xcode-log.sh is missing or not executable: xcodebuild not run"
                exit 1
            fi
            SIM_ID="$(xcrun simctl list devices available iPhone \
                | grep -oE "[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}" | tail -1)"
            if [ -z "$SIM_ID" ]; then
                echo "No available iPhone simulator (see LEARNINGS.md: xcodebuild -downloadPlatform iOS)"
                exit 1
            fi
            scripts/build-kmp-framework.sh --variant uitest || exit 1
            cd iosApp
            xcodebuild test \
                -project TrailMetrics.xcodeproj \
                -scheme TrailMetricsUITests \
                -destination "platform=iOS Simulator,id=$SIM_ID" \
                -only-testing:"$1" \
                -test-timeouts-enabled YES \
                -maximum-test-execution-time-allowance 90 \
                -skipMacroValidation \
                CODE_SIGNING_ALLOWED=NO \
                ARCHS=arm64 \
                EXCLUDED_ARCHS=x86_64 \
                ONLY_ACTIVE_ARCH=NO 2>&1 | "$filter"
        ' _ "$IOS_SMOKE_TEST"
        status=$?
        if [ $status -eq 124 ]; then
            echo "iOS smoke UI test: timeout, the step was killed at the limit of ${IOS_SMOKE_LIMIT} s"
        fi
        echo "iOS smoke UI test: $((SECONDS - started)) s (limit ${IOS_SMOKE_LIMIT} s)"
        return $status
    }
    if [ "$TOUCHES_IOS_UI" = true ]; then
        run_step "iOS smoke UI test" ios_smoke_ui_test
    else
        echo "==> iOS smoke UI test"
        echo "    skipped: no changed file in the UI scope (app, UI tests, package Sources, shared commonMain/iosMain, shared-uitest)"
    fi
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
