#!/usr/bin/env bash
# Keeps the device state of a verification run that did not end as expected, in the run record of the epic
# (running-an-epic.md, "The run record"), before anything clears it. In the first run one locked-screen run never ended
# its session; the next run cleared the log (`logcat -c`) and the one log of the failure was gone, while 24 runs after
# it passed. One log of a failure is worth more than the passes.
#
#   scripts/epic/keep-device-log.sh <epic slug> <label> [--serial <adb serial>]
#   scripts/epic/keep-device-log.sh --self-test
#
# Writes `~/agent-workspace/epics/<slug>/keep-failed-<label>-<UTC time>.log` (the `keep-` prefix keeps the workspace
# cleaner off it; ${TM_EPIC_DIR:-$HOME/agent-workspace/epics} moves the root): the whole of `adb logcat -d`, then
# `dumpsys notification` and `dumpsys activity services` of the device, each under a header line. Run it as the first
# command after the run that failed, before the next run, before `logcat -c`, before an app is force-stopped. It never
# overwrites a file (the name has the time to the second; an existing name gets a numeric suffix), prints the path and the
# size, and exits 1 when `adb` fails or the log is empty (an empty log is not a kept log).
# <label> is lowercase letters, digits and `-`. Exit: 0 kept, 1 failed, 2 usage error. Bash 3.2 compatible.
set -u
ADB="${ADB:-adb}"
USAGE="usage: scripts/epic/keep-device-log.sh <epic slug> <label> [--serial <adb serial>] | --self-test"

keep() {
    local slug="$1" label="$2" serial="${3:-}" root dir file n=1 base tmp
    [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] && [[ "$label" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "$USAGE" >&2; return 2; }
    root="${TM_EPIC_DIR:-$HOME/agent-workspace/epics}"; dir="$root/$slug"
    [ -d "$dir" ] || { echo "keep-device-log: no run record at $dir" >&2; return 1; }
    base="$dir/keep-failed-$label-$(date -u +%Y%m%dT%H%M%SZ)"; file="$base.log"
    while [ -e "$file" ]; do n=$((n + 1)); file="$base-$n.log"; done
    tmp="$(mktemp)" || return 1
    adb_() { if [ -n "$serial" ]; then "$ADB" -s "$serial" "$@"; else "$ADB" "$@"; fi; }
    {
        echo "== adb logcat -d"; adb_ logcat -d
        echo "== dumpsys notification"; adb_ shell dumpsys notification --noredact
        echo "== dumpsys activity services"; adb_ shell dumpsys activity services
    } > "$tmp" 2>&1
    # A device that is not there yields the three headers and nothing between them: not a log.
    if [ "$(grep -vc '^==' "$tmp")" -le 0 ]; then rm -f "$tmp"; echo "keep-device-log: adb gave no log (device not connected?): nothing kept" >&2; return 1; fi
    mv -- "$tmp" "$file"
    echo "kept $file ($(wc -c < "$file" | tr -d ' ') bytes)"
}

self_test() {
    local tmp fails=0 out rc
    tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
    mkdir -p "$tmp/epics/demo"
    printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = logcat ] && { echo line1; echo line2; echo line3; exit 0; }; done\necho dumpsys-output\n' > "$tmp/adb-ok"
    printf '#!/bin/sh\nexit 1\n' > "$tmp/adb-fail"; chmod +x "$tmp/adb-ok" "$tmp/adb-fail"
    t() { # t <description> <expected substring> <expected exit> <adb> <args...>
        local d="$1" want="$2" wantrc="$3" adb="$4"; shift 4
        out="$(ADB="$adb" TM_EPIC_DIR="$tmp/epics" bash "$0" "$@" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$wantrc" ] && printf '%s' "$out" | grep -qF -- "$want"; then echo "ok   $d"
        else echo "FAIL $d: expected exit $wantrc and '$want', got exit $rc: $out" >&2; fails=$((fails + 1)); fi
    }
    t "the log is kept in the run record" "kept $tmp/epics/demo/keep-failed-locked-" 0 "$tmp/adb-ok" demo locked
    t "a second keep in the same second does not overwrite" "kept $tmp/epics/demo/keep-failed-locked-" 0 "$tmp/adb-ok" demo locked --serial emulator-5554
    n="$(ls "$tmp/epics/demo" | grep -c '^keep-failed-locked-')"
    if [ "$n" = 2 ]; then echo "ok   two keeps are two files"; else echo "FAIL two keeps are $n files" >&2; fails=$((fails + 1)); fi
    if grep -q line2 "$tmp/epics/demo"/keep-failed-locked-*.log; then echo "ok   the kept file has the logcat"; else echo "FAIL the kept file has no logcat" >&2; fails=$((fails + 1)); fi
    t "an adb that fails keeps nothing" "nothing kept" 1 "$tmp/adb-fail" demo other
    t "a missing run record is refused" "no run record" 1 "$tmp/adb-ok" nodir x
    t "a bad label is a usage error" "usage:" 2 "$tmp/adb-ok" demo "Bad Label"
    if [ "$fails" = 0 ]; then echo "keep-device-log.sh self-test: all passed"; else echo "keep-device-log.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]; exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    "" | -*) echo "$USAGE" >&2; exit 2 ;;
    *)
        [ "$#" = 2 ] || { [ "$#" = 4 ] && [ "$3" = --serial ]; } || { echo "$USAGE" >&2; exit 2; }
        keep "$1" "$2" "${4:-}"; exit $? ;;
esac
