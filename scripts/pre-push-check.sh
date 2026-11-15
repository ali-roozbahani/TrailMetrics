#!/usr/bin/env bash
# Local quality gate — must pass before an agent (or a human) pushes a branch.
# Mirrors ci.yml's jobs so CI is a confirmation, not a discovery step.
#
# Exit codes: 0 = all required checks passed. Non-zero = do not push.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# One heavy run (Gradle, xcodebuild, this gate) at a time on this machine: start again under
# scripts/heavy-run.sh, which waits while another heavy run is going. Inside it TM_HEAVY_RUN_HELD
# names the live holder and the gate goes on; the Gradle and xcodebuild steps below are covered by it.
if ! { [ -n "${TM_HEAVY_RUN_HELD:-}" ] && kill -0 "$TM_HEAVY_RUN_HELD" 2>/dev/null; }; then
    exec "$REPO_ROOT/scripts/heavy-run.sh" "$REPO_ROOT/scripts/pre-push-check.sh" "$@"
fi

# Remove secret-looking variables (deny list in scripts/scrub-env.sh) from the gate's own
# environment before any step runs: xcodebuild logs the environment of the framework script's
# pre-action and Run Script phase, and no step needs a token. Fail closed: if the file cannot be
# sourced or a matching variable cannot be removed, the gate stops.
if ! source "$REPO_ROOT/scripts/scrub-env.sh" || ! scrub_secret_env; then
    echo "!!  could not remove secret-looking variables from the environment (scripts/scrub-env.sh)"
    echo "Gate stopped before any step. Do not push."
    exit 1
fi

# A shallow clone has no merge-base with origin/main and no history before its boundary, so every base-compared
# step below would be wrong: stop before any of them. Passes in CI (GITHUB_ACTIONS=true), whose checkout is shallow.
if ! scripts/check-full-clone.sh; then
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

# run_limited <seconds> <command> [args...]: runs the command with a hard limit for the whole step. macOS has no
# `timeout`, so a small perl wrapper runs it in its own process group and kills the group (xcodebuild, Gradle, the
# emulator, the simulator's test runner) when the alarm fires; exit code 124 then means the limit was hit. Ctrl-C
# (INT), TERM and HUP reach only the gate's own group, so the wrapper catches them and kills the step's group the
# same way (exit 130, 143, 129); signals are blocked until the child's pid is known.
run_limited() {
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
    ' "$@"
}

# One UI-test step: the platform's runner script under a time limit, with its own elapsed time. The runner prints
# the pins it ran on (emulator and image, simulator and runtime, Xcode). No retry: red is red (tm-testing).
ui_tests_step() {
    local label="$1" limit="$2" started=$SECONDS status
    shift 2
    run_limited "$limit" "$@"
    status=$?
    if [ $status -eq 124 ]; then
        echo "$label: timeout, the step was killed at the limit of ${limit} s"
    fi
    echo "$label: $((SECONDS - started)) s (limit ${limit} s)"
    return $status
}
# Limits for the whole step, from the measured times on the owner's Mac (2026-11-15; iOS: 9 tests, 230 s with the
# variant framework built; Android: 3 tests, 94 s with a warm daemon), with room for a cold build.
ANDROID_UI_LIMIT=420
IOS_UI_LIMIT=720

# >>> iOS scope: BASE_REF, CHANGED_FILES, TOUCHES_IOS_OR_SHARED (begin) >>>
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
    done <"$IOS_SCOPE_TMP/list"
fi
[ -n "$IOS_SCOPE_TMP" ] && rm -rf "$IOS_SCOPE_TMP"
if [ -n "$IOS_SCOPE_PROBLEM" ]; then
    TOUCHES_IOS_OR_SHARED=true
    echo "Warning: the changed-file list for the iOS scope is not exact: $IOS_SCOPE_PROBLEM"
    echo "         iOS/shared checks required: true (fail-safe)"
fi
# <<< iOS scope: BASE_REF, CHANGED_FILES, TOUCHES_IOS_OR_SHARED (end) <<<

# --- Decide scope: may the heavy steps be skipped? ---
# scripts/classify-changes.sh decides it, the same script as CI. "light" (no changed file can affect
# the Android or iOS build or tests: its allowlist, minus its heavy scripts) skips the Android/KMP steps and the iOS steps; anything else,
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

# Which platform's UI tests this branch needs: the classifier decides (`--ui-scope`: androidApp only Android;
# iosApp and shared-uitest only iOS; domain, data, core, shared and the root Gradle and catalog files both; docs,
# skills and tooling scripts none; anything else both). The full suite of each runs, never a single test. Fail-safe:
# no merge-base, an error or an answer that is not one of the four values is `both`.
UI_SCOPE=both
if [ "$BASE_REF" != HEAD~1 ] && UI_SCOPE_OUT="$(scripts/classify-changes.sh --ui-scope --base "$BASE_REF" 2>&1)"; then
    case "${UI_SCOPE_OUT%%$'\n'*}" in
        'ui-scope: android') UI_SCOPE=android ;;
        'ui-scope: ios') UI_SCOPE=ios ;;
        'ui-scope: none') UI_SCOPE=none ;;
    esac
fi
RUN_ANDROID_UI=false
RUN_IOS_UI=false
if [ "$DECISION" = full ]; then
    case "$UI_SCOPE" in
        android) RUN_ANDROID_UI=true ;;
        ios) RUN_IOS_UI=true ;;
        both) RUN_ANDROID_UI=true; RUN_IOS_UI=true ;;
    esac
fi

# One flag for both the secrets config check and the iOS steps below, so the iOS steps never run
# without that check having run first. The iOS UI tests need the same builds, so they set it too.
RUN_IOS_STEPS=false
if [ "$DECISION" = full ] && { [ "$TOUCHES_IOS_OR_SHARED" = true ] || [ "$RUN_IOS_UI" = true ]; }; then
    RUN_IOS_STEPS=true
fi

echo "Changed files since $BASE_REF:"
echo "$CHANGED_FILES" | sed 's/^/  /'
echo "iOS/shared checks required: $TOUCHES_IOS_OR_SHARED"
echo "UI tests required: $UI_SCOPE (Android: $RUN_ANDROID_UI, iOS: $RUN_IOS_UI)"
echo

# --base: the slug of a record this branch deleted must not be named in any other file (CI: same check, base fetched by the script).
run_step "board check" scripts/check-board.sh --base "$BASE_REF"

# Protected paths (.github/CODEOWNERS): the file must be valid. Same command as CI's tooling job.
run_step "protected paths" scripts/check-protected-paths.sh --validate

# A diff that touches .github/workflows/pr-review.yml, or adds a reference to secrets in a workflow file, is pushed
# by the owner, not the agent (tm-agent-loop, section 5). The push hook allows a push only after this gate passed,
# so a failure here keeps the agent from pushing such a branch. Every other workflow change passes.
run_step "workflow guard" scripts/check-workflow-guard.sh --base "$BASE_REF"

# scripts/README.md indexes every script under scripts/ (one line each). Same as CI's tooling job.
run_step "scripts index check" scripts/checks/scripts-index.sh --check

# The list of heavy scripts (scripts/classify-changes.sh) must name every script that a build or test
# step runs, or a script change would be called light by mistake. In CI `classify-changes.sh --github`
# runs the same check first and fails its step.
run_step "heavy scripts check" scripts/check-heavy-scripts.sh

# Script self-tests: the lists scripts/checks/self-tests-tooling.list and scripts/checks/self-tests.list, which
# CI runs too. Their check fails when a script with a --self-test is on neither. One gate step per line, so the output
# still names each self-test; the list is read on fd 3, so a self-test cannot read it from
# stdin. Fail closed: a list that cannot be read is a failure, not zero steps.
run_step "self-test list check" scripts/checks/self-tests.sh --check
if SELF_TESTS="$(scripts/checks/self-tests.sh --list tooling macos)"; then
    while IFS=$'\t' read -r -u 3 SELF_TEST_NAME SELF_TEST_SCRIPT; do
        run_step "$SELF_TEST_NAME" "$SELF_TEST_SCRIPT" --self-test
    done 3<<< "$SELF_TESTS"
else
    FAILURES+=("self-test list (scripts/checks/self-tests.sh --list tooling macos failed)")
fi

# Coverage floors (config/kover-floors.properties) only go up: compared with the merge base, in
# every classification, light included (no Gradle needed). Same check as CI's tooling job, which
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
# check as CI's tooling job, which compares with the PR's base commit. Fail closed as above.
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
    echo "    no changed file can affect the Android or iOS build or tests: Android/KMP and iOS steps skipped"
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

    # The Android UI tests: the full instrumented suite on the dedicated AVD (scripts/android-ui-tests.sh boots
    # it, prints the emulator, image, API and ABI it ran on, and goes through heavy-run like every Gradle run).
    if [ "$RUN_ANDROID_UI" = true ]; then
        run_step "Android UI tests" ui_tests_step "Android UI tests" "$ANDROID_UI_LIMIT" scripts/android-ui-tests.sh
    else
        echo "==> Android UI tests"
        echo "    skipped: the UI scope of this branch is $UI_SCOPE"
    fi
fi

# --- iOS (only when relevant files changed, and the decision is full) ---
if [ "$RUN_IOS_STEPS" = true ]; then
    if command -v swiftlint >/dev/null 2>&1; then
        run_step "swiftlint" bash -c 'cd iosApp && swiftlint lint --strict'
    else
        FAILURES+=("swiftlint (not installed — install with 'brew install swiftlint')")
    fi

    # The SwiftLint rules' self-tests, group `ios-swiftlint` of scripts/checks/self-tests.list: the
    # two rules that keep hardcoded user-visible strings out of iOS code, and the `optional_try`
    # custom rule with its "Invalid configuration" check. They need swiftlint, like the step above.
    if command -v swiftlint >/dev/null 2>&1; then
        if SELF_TESTS="$(scripts/checks/self-tests.sh --list ios-swiftlint)"; then
            while IFS=$'\t' read -r -u 3 SELF_TEST_NAME SELF_TEST_SCRIPT; do
                run_step "$SELF_TEST_NAME" "$SELF_TEST_SCRIPT" --self-test
            done 3<<< "$SELF_TESTS"
        else
            FAILURES+=("self-test list (scripts/checks/self-tests.sh --list ios-swiftlint failed)")
        fi
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

    # The iOS UI tests: the full suite of scheme TrailMetricsUITests on the pinned simulator
    # (scripts/ios-ui-tests.sh builds the test-only variant, prints the simulator, runtime and Xcode it ran
    # on and filters the log through scripts/filter-xcode-log.sh). Only when the branch's UI scope includes iOS.
    # Last in the iOS part: `--variant uitest` leaves the test-only framework at the debug path, and a normal
    # build after it rebuilds the production one.
    if [ "$RUN_IOS_UI" = true ]; then
        run_step "iOS UI tests" ui_tests_step "iOS UI tests" "$IOS_UI_LIMIT" scripts/ios-ui-tests.sh
    else
        echo "==> iOS UI tests"
        echo "    skipped: the UI scope of this branch is $UI_SCOPE (decision $DECISION)"
    fi
fi
if [ "$RUN_IOS_STEPS" != true ]; then
    echo "==> iOS UI tests"
    echo "    skipped: the UI scope of this branch is $UI_SCOPE (decision $DECISION)"
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
