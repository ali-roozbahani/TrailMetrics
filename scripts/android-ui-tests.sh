#!/usr/bin/env bash
# Runs the Android instrumented tests (androidApp/app/src/androidTest) on a dedicated emulator.
#
#   scripts/android-ui-tests.sh [--tests <class-or-method>] [--keep-emulator]
#
# The emulator is an AVD of this script's own, TrailMetrics_UITest, on its own console port. The
# developer's own AVDs (Pixel_10 and any other) are never started, wiped, copied or installed on:
#   - the AVD directory is written from the explicit config below, with no user data copied from another AVD;
#   - the emulator starts headless with -wipe-data on port $PORT, so its serial is $SERIAL;
#   - every adb and Gradle call is pinned with ANDROID_SERIAL=$SERIAL, so a second device that is attached
#     (the developer's emulator, a phone) is never a target;
#   - if $SERIAL is already attached, the script refuses instead of reusing it (it may not be ours).
# It prints the pins the run used (emulator version, image, API level, ABI) so a gate log says on what it ran.
# The Gradle call goes through scripts/heavy-run.sh (one heavy run at a time on this Mac).
# No retries: the emulator is started once and the tests run once. Exit status is the tests' (1 for a failure),
# 2 for an environment problem (no SDK, the emulator did not boot).
set -euo pipefail

AVD_NAME="TrailMetrics_UITest"
PORT=5560
SERIAL="emulator-${PORT}"
SYSTEM_IMAGE="system-images/android-37.1/google_apis_playstore_ps16k/arm64-v8a/"
BOOT_TIMEOUT_S=240
SHUTDOWN_TIMEOUT_S=30

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
EMULATOR="$SDK/emulator/emulator"
ADB="$SDK/platform-tools/adb"
AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.android/avd}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tests_filter=""
keep_emulator=0
while [ $# -gt 0 ]; do
    case "$1" in
        --tests) tests_filter="${2:?--tests needs a class or method}"; shift 2 ;;
        --keep-emulator) keep_emulator=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "android-ui-tests: unknown argument: $1" >&2; exit 2 ;;
    esac
done

fail_env() { echo "android-ui-tests: $*" >&2; exit 2; }

[ -x "$EMULATOR" ] || fail_env "no emulator at $EMULATOR (set ANDROID_HOME)"
[ -x "$ADB" ] || fail_env "no adb at $ADB (set ANDROID_HOME)"
[ -d "$SDK/$SYSTEM_IMAGE" ] || fail_env "system image $SYSTEM_IMAGE is not installed in $SDK"

create_avd() {
    local dir="$AVD_HOME/$AVD_NAME.avd"
    mkdir -p "$dir"
    cat > "$AVD_HOME/$AVD_NAME.ini" <<EOF
avd.ini.encoding=UTF-8
path=$dir
path.rel=avd/$AVD_NAME.avd
target=android-37.1
EOF
    cat > "$dir/config.ini" <<EOF
AvdId=$AVD_NAME
PlayStore.enabled=true
abi.type=arm64-v8a
avd.ini.displayname=TrailMetrics UI tests
avd.ini.encoding=UTF-8
disk.dataPartition.size=8G
hw.cpu.arch=arm64
hw.cpu.ncore=4
hw.device.manufacturer=Google
hw.device.name=pixel_10
hw.gps=yes
hw.keyboard=yes
hw.lcd.density=420
hw.lcd.height=2424
hw.lcd.width=1080
hw.mainKeys=no
hw.ramSize=4096
hw.sdCard=no
image.sysdir.1=$SYSTEM_IMAGE
tag.display=Google APIs PlayStore
tag.id=google_apis_playstore
target=android-37.1
EOF
}

if "$ADB" devices | awk 'NR>1 {print $1}' | grep -qx "$SERIAL"; then
    fail_env "$SERIAL is already attached; it is not started by this run, so it is not reused. Stop it first."
fi

create_avd

emulator_pid=""
cleanup() {
    if [ "$keep_emulator" -eq 0 ] && [ -n "$emulator_pid" ]; then
        "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
        wait "$emulator_pid" 2>/dev/null || true
        # adb lists the serial for a moment after the process is gone; the next run refuses a listed serial.
        local gone_deadline=$(( $(date +%s) + SHUTDOWN_TIMEOUT_S ))
        while "$ADB" devices | awk 'NR>1 {print $1}' | grep -qx "$SERIAL" && [ "$(date +%s)" -lt "$gone_deadline" ]; do
            sleep 1
        done
    fi
}
trap cleanup EXIT

LOG_DIR="${TMPDIR:-/tmp}/android-ui-tests"
mkdir -p "$LOG_DIR"
"$EMULATOR" -avd "$AVD_NAME" -port "$PORT" -no-window -no-audio -no-snapshot -wipe-data -no-boot-anim \
    > "$LOG_DIR/emulator.log" 2>&1 &
emulator_pid=$!

deadline=$(( $(date +%s) + BOOT_TIMEOUT_S ))
until [ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    kill -0 "$emulator_pid" 2>/dev/null || fail_env "the emulator exited before it booted (log: $LOG_DIR/emulator.log)"
    [ "$(date +%s)" -lt "$deadline" ] || fail_env "the emulator did not boot in ${BOOT_TIMEOUT_S}s (log: $LOG_DIR/emulator.log)"
    sleep 2
done

api="$("$ADB" -s "$SERIAL" shell getprop ro.build.version.sdk | tr -d '\r')"
abi="$("$ADB" -s "$SERIAL" shell getprop ro.product.cpu.abi | tr -d '\r')"
emu_version="$("$EMULATOR" -version 2>/dev/null | sed -n 's/.*emulator version \([0-9.]*\).*/\1/p' | head -1)"
echo "android-ui-tests: AVD $AVD_NAME on $SERIAL, image $SYSTEM_IMAGE, API $api, ABI $abi, emulator $emu_version"

export ANDROID_SERIAL="$SERIAL"
gradle_args=(:androidApp:app:connectedDebugAndroidTest)
if [ -n "$tests_filter" ]; then
    gradle_args+=("-Pandroid.testInstrumentationRunnerArguments.class=$tests_filter")
fi
cd "$ROOT"
status=0
scripts/heavy-run.sh ./gradlew "${gradle_args[@]}" || status=$?
exit "$status"
