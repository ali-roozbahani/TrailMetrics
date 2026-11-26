#!/usr/bin/env bash
# Runs the iOS UI tests (scheme TrailMetricsUITests, the full suite unless --tests names a part) once, on a
# dedicated simulator of this script's own. The full suite leaves out LaunchPerformanceTests (a launch-time
# measurement that asserts no timing, run on request: docs/performance/ios-cold-start.md; owner decision of
# 2026-11-26), so the gate and the full run on main never run it; --tests can still name it.
#
#   scripts/ios-ui-tests.sh [--tests <TrailMetricsUITests/Class[/method]>]
#
# The pins, printed at the start of every run so a gate log says on what it ran: the device type and the
# runtime below, and the Xcode that `xcodebuild -version` names. The simulator is called TrailMetrics_UITest
# and is created here when it is missing (or recreated when a device of that name has another type or
# runtime). Any other simulator on the machine is never booted, erased or used. It is shut down and erased
# before each run, so no test depends on the state of an earlier one, and shut down again at the end.
# The test-only framework variant is built first (scripts/build-kmp-framework.sh --variant uitest), the
# xcodebuild output goes through scripts/filter-xcode-log.sh (the local secrets config holds a real Maps key),
# and there is no retry: red is red (docs/epics/ios-ui-tests.md, D6).
# Exit status: xcodebuild's (65 for a failed test); 2 for an environment problem (the runtime is not installed,
# the simulator could not be created or booted). A time limit is the caller's (the gate's `run_limited`).
set -uo pipefail

SIM_NAME="TrailMetrics_UITest"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17"
DEVICE_TYPE_NAME="iPhone 17"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
RUNTIME_NAME="iOS 26.5"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
only=""
while [ $# -gt 0 ]; do
    case "$1" in
        --tests) only="${2:?--tests needs TrailMetricsUITests/Class[/method]}"; shift 2 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "ios-ui-tests: unknown argument: $1" >&2; exit 2 ;;
    esac
done

fail_env() { echo "ios-ui-tests: $*" >&2; exit 2; }

filter="$ROOT/scripts/filter-xcode-log.sh"
[ -x "$filter" ] || fail_env "scripts/filter-xcode-log.sh is missing or not executable: xcodebuild not run"
command -v xcrun >/dev/null 2>&1 || fail_env "xcrun not found"
command -v python3 >/dev/null 2>&1 || fail_env "python3 not found"
xcrun simctl list runtimes available | grep -qF "$RUNTIME" \
    || fail_env "the pinned runtime $RUNTIME_NAME ($RUNTIME) is not installed (see LEARNINGS.md: xcodebuild -downloadPlatform iOS)"

# The simulator named $SIM_NAME with the pinned type and runtime: its UDID, or nothing. Another device of that
# name (an older pin) is ours too: it is deleted so that the pin is exact.
find_sim() {
    xcrun simctl list devices -j | python3 -I -c '
import json, sys
name, dtype, runtime, mode = sys.argv[1:5]
data = json.load(sys.stdin)["devices"]
for rt, devices in data.items():
    for d in devices:
        if d.get("name") != name:
            continue
        ok = rt == runtime and d.get("deviceTypeIdentifier") == dtype and d.get("isAvailable", False)
        if mode == "stale" and not ok:
            print(d["udid"])
        if mode == "good" and ok:
            print(d["udid"])
' "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME" "$1"
}

for stale in $(find_sim stale); do
    xcrun simctl shutdown "$stale" >/dev/null 2>&1 || true
    xcrun simctl delete "$stale" || fail_env "could not delete the stale simulator $stale"
done
SIM_ID="$(find_sim good | head -1)"
if [ -z "$SIM_ID" ]; then
    SIM_ID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")" || fail_env "could not create the simulator"
fi

cleanup() { xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true
xcrun simctl erase "$SIM_ID" || fail_env "could not erase the simulator $SIM_ID"
xcrun simctl boot "$SIM_ID" || fail_env "could not boot the simulator $SIM_ID"
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null 2>&1 || fail_env "the simulator $SIM_ID did not finish booting"

runtime_build="$(xcrun simctl list runtimes | grep -F "$RUNTIME" | sed -n 's/.*(\([0-9.]*\) - \([A-Za-z0-9]*\)).*/\1 \2/p' | head -1)"
xcode="$(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
echo "ios-ui-tests: simulator $SIM_NAME $SIM_ID, $DEVICE_TYPE_NAME, $RUNTIME_NAME (${runtime_build:-unknown}), $xcode"

cd "$ROOT" || fail_env "cannot enter $ROOT"
scripts/build-kmp-framework.sh --variant uitest || exit 1
cd iosApp || fail_env "no iosApp directory"
args=(
    test
    -project TrailMetrics.xcodeproj
    -scheme TrailMetricsUITests
    -destination "platform=iOS Simulator,id=$SIM_ID"
    -test-timeouts-enabled YES
    -maximum-test-execution-time-allowance 90
    -skipMacroValidation
)
if [ -n "$only" ]; then
    args+=(-only-testing:"$only")
else
    args+=(-skip-testing:TrailMetricsUITests/LaunchPerformanceTests)
fi
args+=(CODE_SIGNING_ALLOWED=NO ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO)
set -o pipefail
xcodebuild "${args[@]}" 2>&1 | "$filter"
exit "${PIPESTATUS[0]}"
