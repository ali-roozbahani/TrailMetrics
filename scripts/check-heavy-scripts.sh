#!/usr/bin/env bash
# Keeps the list of heavy scripts complete. scripts/classify-changes.sh calls a change to a tooling
# script light (CI's Android and iOS jobs and the gate skip their build and test steps), except for the
# scripts on its HEAVY_SCRIPTS list. This check fails when something that a heavy step runs would
# classify light: the Xcode project's build phases and scheme pre-actions, Gradle, the steps of
# .github/workflows/ci.yml that a light decision skips, the gate's DECISION and RUN_IOS_STEPS blocks,
# the self-tests only the iOS job runs, and what those scripts start themselves. A script added later
# that one of them runs therefore fails here, with the file that runs it, instead of being missed
# silently. The reading rules are in check-heavy-scripts.py's header.
#
#   scripts/check-heavy-scripts.sh [--root <dir>]   the repository this script is in, or <dir>
#   scripts/check-heavy-scripts.sh --self-test      inline cases, each a small repository
#
# Run by the gate (every classification) and first by `classify-changes.sh --github`, which fails its
# CI step on a failure. Exit 0 ok, 1 a script is missing from the list, 2 usage or environment error.
# python3 standard library only (present on macOS and ubuntu-latest). Bash 3.2 compatible.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

self_test() {
    local tmp fails=0 repo out rc n=0
    tmp="$(mktemp -d)"
    TMP_ROOT="$tmp"
    trap 'rm -rf -- "$TMP_ROOT"' EXIT
    # fresh <name>: an empty repository directory $repo with one tooling script and one heavy script.
    fresh() {
        n=$((n + 1)); repo="$tmp/case$n"
        mkdir -p "$repo/scripts" "$repo/.github/workflows" "$repo/iosApp/TrailMetrics.xcodeproj"
        printf '#!/bin/sh\n' > "$repo/scripts/new-tool.sh"
        printf '#!/bin/sh\n' > "$repo/scripts/build-kmp-framework.sh"
    }
    put() { mkdir -p "$(dirname "$repo/$1")"; cat > "$repo/$1"; }
    expect() { # expect <description> <exit> <substring or empty>
        out="$(bash "$SCRIPT_DIR/check-heavy-scripts.sh" --root "$repo" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$2" ] && { [ -z "$3" ] || printf '%s' "$out" | grep -qF -- "$3"; }; then echo "ok   $1"; else
            echo "FAIL $1: expected exit $2${3:+ and '$3'}, got exit $rc:" >&2; printf '%s\n' "$out" | sed 's/^/       /' >&2; fails=$((fails + 1)); fi
    }

    fresh; expect "a repository with no heavy-step source: nothing to check" 0 "nothing checked"

    fresh
    put iosApp/TrailMetrics.xcodeproj/project.pbxproj <<'EOF'
shellScript = "scripts/build-kmp-framework.sh";
EOF
    put .github/workflows/ci.yml <<'EOF'
jobs:
  android:
    steps:
      - name: Always
        run: scripts/new-tool.sh
      - name: Build
        if: steps.changes.outputs.decision != 'light'
        run: scripts/build-kmp-framework.sh
EOF
    expect "everything that heavy steps run is listed; a light step may run an unlisted script" 0 "OK"

    fresh
    put iosApp/TrailMetrics.xcodeproj/project.pbxproj <<'EOF'
shellScript = "scripts/new-tool.sh";
EOF
    expect "the Xcode project runs an unlisted script" 1 "scripts/new-tool.sh is started by iosApp/TrailMetrics.xcodeproj/project.pbxproj"

    fresh
    put .github/workflows/ci.yml <<'EOF'
jobs:
  android:
    steps:
      - name: Heavy step
        if: steps.changes.outputs.decision != 'light'
        run: scripts/new-tool.sh
EOF
    expect "a CI step skipped on light runs an unlisted script" 1 "step 'Heavy step'"

    fresh
    put .github/workflows/ci.yml <<'EOF'
jobs:
  ios-main:
    name: iOS 2b
    needs: ios-plan
    if: needs.ios-plan.outputs.decision != 'light'
    steps:
      - name: Anything
        run: scripts/new-tool.sh
EOF
    expect "a step of a job skipped on light runs an unlisted script" 1 "step 'Anything'"

    fresh
    put .github/workflows/ci.yml <<'EOF'
jobs:
  tooling:
    steps:
      - name: Self-tests
        run: scripts/new-tool.sh
  other:
    steps:
      - name: Mentioned only in a comment
        run: echo hi # scripts/new-tool.sh
      # scripts/new-tool.sh
      - name: Build
        if: steps.changes.outputs.decision != 'light'
        run: echo no script
EOF
    expect "an always-run step, and a comment, are not heavy references" 0 "OK"

    fresh
    put scripts/pre-push-check.sh <<'EOF'
#!/usr/bin/env bash
scripts/new-tool.sh
if [ "$DECISION" = full ]; then
    # scripts/new-tool.sh in a comment
    run_step "build" scripts/build-kmp-framework.sh
fi
EOF
    expect "the gate runs an unlisted script outside its heavy blocks and a listed one inside: ok" 0 "OK"
    put scripts/pre-push-check.sh <<'EOF'
#!/usr/bin/env bash
if [ "$RUN_IOS_STEPS" = true ]; then
    if command -v swiftlint; then
        run_step "x" scripts/new-tool.sh
    fi
fi
EOF
    expect "the gate runs an unlisted script inside a heavy block" 1 "scripts/new-tool.sh is started by scripts/pre-push-check.sh"

    fresh
    printf '#!/bin/sh\n# scripts/new-tool.sh is not started here\nscripts/new-tool.sh\n' > "$repo/scripts/build-kmp-framework.sh"
    put iosApp/TrailMetrics.xcodeproj/project.pbxproj <<'EOF'
shellScript = "scripts/build-kmp-framework.sh";
EOF
    expect "a heavy script starts an unlisted one" 1 "scripts/new-tool.sh is started by scripts/build-kmp-framework.sh"
    printf '#!/bin/sh\n# scripts/new-tool.sh is not started here\n' > "$repo/scripts/build-kmp-framework.sh"
    expect "a heavy script that only names it in a comment: ok" 0 "OK"

    fresh
    put app/build.gradle.kts <<'EOF'
// scripts/new-tool.sh in a comment
tasks.register<Exec>("x") { commandLine("scripts/new-tool.sh") }
EOF
    expect "a Gradle build file runs an unlisted script" 1 "scripts/new-tool.sh is started by app/build.gradle.kts"

    # The self-test groups come from ci.yml: a group run only by a step a light decision skips is heavy.
    fresh
    put .github/workflows/ci.yml <<'EOF'
jobs:
  tooling:
    steps:
      - name: Self-tests
        run: scripts/checks/self-tests.sh --run tooling
  ios-main:
    if: needs.ios-plan.outputs.decision != 'light'
    steps:
      - name: Script self-tests (iOS)
        run: scripts/checks/self-tests.sh --run ios-swiftlint macos
EOF
    printf 'tooling\tA\tscripts/new-tool.sh\nmacos\tB\tscripts/new-tool.sh\n' | put scripts/checks/self-tests.list
    expect "a self-test of a group only a heavy CI step runs is an unlisted script" 1 "group macos"
    printf 'tooling\tA\tscripts/new-tool.sh\n' | put scripts/checks/self-tests.list
    expect "a tooling-group self-test is not a heavy reference" 0 "OK"
    put .github/workflows/ci.yml <<'EOF'
jobs:
  ios-main:
    if: needs.ios-plan.outputs.decision != 'light'
    steps:
      - name: Script self-tests (iOS)
        run: scripts/checks/self-tests.sh --run brand-new-group
EOF
    printf 'brand-new-group\tA\tscripts/new-tool.sh\n' | put scripts/checks/self-tests.list
    expect "a new heavy-only group is derived from ci.yml, not from a fixed list" 1 "group brand-new-group"
    printf 'orphan\tA\tscripts/new-tool.sh\n' | put scripts/checks/self-tests.list
    expect "a group that no ci.yml step runs is a problem" 1 "is run by no step of ci.yml"
    rm -f "$repo/.github/workflows/ci.yml"
    expect "a self-test list without a ci.yml is a problem" 1 "no .github/workflows/ci.yml"

    # A source that exists and cannot be read is an error, never a pass.
    if [ "$(id -u)" != 0 ]; then
        fresh
        put iosApp/TrailMetrics.xcodeproj/project.pbxproj <<'EOF'
shellScript = "scripts/build-kmp-framework.sh";
EOF
        chmod 000 "$repo/iosApp/TrailMetrics.xcodeproj/project.pbxproj"
        expect "an unreadable Xcode project file exits 2" 2 "cannot be read"
        chmod 644 "$repo/iosApp/TrailMetrics.xcodeproj/project.pbxproj"
        fresh
        put .github/workflows/ci.yml <<'EOF'
jobs: {}
EOF
        chmod 000 "$repo/.github/workflows/ci.yml"
        expect "an unreadable ci.yml exits 2" 2 "cannot be read"
        chmod 644 "$repo/.github/workflows/ci.yml"
    fi

    fresh
    put iosApp/TrailMetrics.xcodeproj/project.pbxproj <<'EOF'
shellScript = "scripts/does-not-exist.sh";
EOF
    expect "a reference to a file that does not exist is ignored" 0 "OK"

    out="$(bash "$SCRIPT_DIR/check-heavy-scripts.sh" 2>&1)" && rc=0 || rc=$?
    if [ "$rc" = 0 ]; then echo "ok   this repository's list is complete"; else
        echo "FAIL this repository: exit $rc: $out" >&2; fails=$((fails + 1)); fi
    out="$(bash "$SCRIPT_DIR/check-heavy-scripts.sh" --bogus 2>&1)" && rc=0 || rc=$?
    if [ "$rc" = 2 ]; then echo "ok   a usage error exits 2"; else echo "FAIL usage error: exit $rc" >&2; fails=$((fails + 1)); fi

    if [ "$fails" -eq 0 ]; then echo "check-heavy-scripts self-test: all passed"; else echo "check-heavy-scripts self-test: $fails failed" >&2; fi
    [ "$fails" -eq 0 ]
}

if [ "${1:-}" = --self-test ]; then
    [ $# -eq 1 ] || { echo "usage: scripts/check-heavy-scripts.sh [--root <dir>] | --self-test" >&2; exit 2; }
    self_test
    exit $?
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "check-heavy-scripts: python3 not found" >&2
    exit 2
fi
exec python3 "$SCRIPT_DIR/check-heavy-scripts.py" "$@"
