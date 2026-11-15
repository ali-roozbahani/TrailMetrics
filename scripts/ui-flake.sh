#!/usr/bin/env bash
# Local UI flakes: a UI-test run of the gate or of the main run that fails and then passes with no related
# change is counted and logged like a CI flake (owner decision of 2026-11-15, step 4). There is no retry anywhere:
# this script only records what already ran, and says when a pass follows a failure that nothing explains.
#
#   scripts/ui-flake.sh --record --platform <android|ios> --result <pass|fail> --log <file> --context <gate|main>
#                       [--sha <sha>]      called after every UI-test step of the gate and of scripts/main-ui-run.sh
#   scripts/ui-flake.sh --pending           the flakes detected and not yet in CI_FLAKES.md, one block each
#   scripts/ui-flake.sh --pending-count     just the number
#   scripts/ui-flake.sh --logged <id>       mark one as logged (after the entry or occurrence is in CI_FLAKES.md)
#   scripts/ui-flake.sh --self-test
#
# What is recorded. Every run is one line of the history (time, commit, platform, result, context, signature). The
# signature of a failure is `Class.test: first error message` read from the run's log (xcodebuild's
# `error: -[TrailMetricsUITests.Class test] : message`, the Android runner's `Class > test[...] FAILED` and the
# assertion under it); a failure before any test ran (a build, the emulator, the simulator) has the last line of the log.
#
# What is a flake. A pass whose previous run on the same platform (the gate or the main run, any branch) failed, when
# nothing related changed in between: the same commit, or a later one (the failed commit is an ancestor of the
# passing one) whose changes since then are, by `scripts/classify-changes.sh --ui-scope`, not in that platform's
# UI scope (none, or the other platform only). A pass after a fix in the platform's scope, or on an unrelated
# branch, is not a flake: the script says why. A flake is added to the pending list with the evidence for
# CI_FLAKES.md; `--record` never fails the caller and never changes the test result: exit 0 unless the
# usage is wrong (2).
#
# Where it lives: ${TM_UI_FLAKE_DIR:-~/agent-workspace/ui-flakes}/history.tsv, pending.tsv and logged.tsv (a folder
# of the agent workspace, which the cleaner does not delete). The gate prints the pending flakes in a report-only
# step and `scripts/main-ui-run.sh --status` the number, so one is not forgotten; the rule for logging them is
# tm-pr-workflow, "Flake log".
# Bash 3.2 compatible.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
DIR="${TM_UI_FLAKE_DIR:-$HOME/agent-workspace/ui-flakes}"
HISTORY="$DIR/history.tsv"
PENDING="$DIR/pending.tsv"
LOGGED="$DIR/logged.tsv"

usage() { sed -n '2,8p' "$SELF" >&2; echo "usage: scripts/ui-flake.sh --record ... | --pending | --pending-count | --logged <id> | --self-test" >&2; exit 2; }

short() { printf '%s' "${1:0:8}"; }

# The signature of a failed run, from its log.
signature() { # <platform> <log>
    local platform="$1" log="$2" sig=""
    [ -f "$log" ] || { echo "no log of the run"; return; }
    local clean
    clean="$(perl -pe 's/\e\[[0-9;]*[A-Za-z]//g; s/\r//g' "$log" 2>/dev/null)"
    if [ "$platform" = ios ]; then
        sig="$(printf '%s\n' "$clean" | sed -n 's/.*error: -\[TrailMetricsUITests\.\([A-Za-z0-9_]*\) \([A-Za-z0-9_]*\)\] : \(.*\)$/\1.\2: \3/p' | head -n 1)"
    else
        sig="$(printf '%s\n' "$clean" | awk '
            /^[A-Za-z0-9_.]+ > [A-Za-z0-9_]+\[.*FAILED/ { n = $0; sub(/^.*\.([A-Za-z0-9_]+) > /, "&", n); split($0, a, " > "); cls = a[1]; sub(/^.*\./, "", cls); t = a[2]; sub(/\[.*$/, "", t); name = cls "." t; want = 1; next }
            want && NF { m = $0; sub(/^[ \t]*(java\.lang\.)?/, "", m); print name ": " m; exit }')"
    fi
    if [ -z "$sig" ]; then
        sig="before any test: $(printf '%s\n' "$clean" | grep -v '^[[:space:]]*$' | tail -n 1)"
    fi
    printf '%s' "$sig" | sed -E 's/0x[0-9a-fA-F]+/0x../g' | cut -c1-220
}

# 0 when the platform's UI tests could be affected by the changes from $1 to HEAD (or the answer is unknown).
related_change() { # <platform> <from sha>
    local scope
    scope="$("$ROOT/scripts/classify-changes.sh" --root "$ROOT" --ui-scope --base "$2" 2>/dev/null | head -n 1)"
    case "$scope" in
        'ui-scope: none') return 1 ;;
        'ui-scope: android') [ "$1" = android ] ;;
        'ui-scope: ios') [ "$1" = ios ] ;;
        *) return 0 ;;
    esac
}

count_of() { # <platform> <signature>: how many flakes of this signature are pending or logged
    local n=0 f
    for f in "$PENDING" "$LOGGED"; do
        [ -f "$f" ] && n=$((n + $(awk -F '\t' -v p="$1" -v s="$2" '$2 == p && $3 == s {c++} END {print c + 0}' "$f")))
    done
    echo "$n"
}

cmd_record() {
    local platform="" result="" log="" context="" sha="" now sig prev p_time p_sha p_result p_context id count
    while [ $# -gt 0 ]; do
        case "$1" in
            --platform) platform="${2:-}"; shift 2 ;;
            --result) result="${2:-}"; shift 2 ;;
            --log) log="${2:-}"; shift 2 ;;
            --context) context="${2:-}"; shift 2 ;;
            --sha) sha="${2:-}"; shift 2 ;;
            *) usage ;;
        esac
    done
    case "$platform" in android | ios) ;; *) usage ;; esac
    case "$result" in pass | fail) ;; *) usage ;; esac
    case "$context" in gate | main) ;; *) usage ;; esac
    [ -n "$sha" ] || sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
    mkdir -p "$DIR" 2>/dev/null || { echo "ui-flake: cannot create $DIR: nothing recorded"; return 0; }
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sig="-"
    [ "$result" = fail ] && sig="$(signature "$platform" "$log")"
    prev="$(awk -F '\t' -v p="$platform" '$3 == p {l = $0} END {print l}' "$HISTORY" 2>/dev/null)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$sha" "$platform" "$result" "$context" "$sig" >> "$HISTORY"
    if [ "$result" = fail ]; then
        echo "ui-flake: recorded the $platform UI failure on $(short "$sha") ($context): $sig"
        return 0
    fi
    [ -n "$prev" ] || return 0
    IFS=$'\t' read -r p_time p_sha p_result p_context sig_prev <<<"$(printf '%s' "$prev" | awk -F '\t' '{print $1 "\t" $2 "\t" $4 "\t" $5 "\t" $6}')"
    [ "$p_result" = fail ] || return 0
    sig="$sig_prev"
    if [ "$p_sha" != "$sha" ]; then
        if ! git -C "$ROOT" merge-base --is-ancestor "$p_sha" "$sha" 2>/dev/null; then
            echo "ui-flake: the $platform UI tests passed; the failure before it ($(short "$p_sha"), $p_context) is not on this commit's history: not counted as a flake"
            return 0
        fi
        if related_change "$platform" "$p_sha"; then
            echo "ui-flake: the $platform UI tests passed after a failure on $(short "$p_sha"); the commits since then change that platform's UI scope: not counted as a flake"
            return 0
        fi
    fi
    id="$(printf '%s' "$now" | tr -d ':-' | tr 'TZ' '-')$platform"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$platform" "$sig" "$p_sha" "$p_time" "$p_context" "$sha" "$now" "$context" >> "$PENDING"
    count="$(count_of "$platform" "$sig")"
    echo "ui-flake: FLAKE $id: $platform UI tests: $sig"
    echo "    failed $p_time on $(short "$p_sha") ($p_context), passed $now on $(short "$sha") ($context); nothing that changes the $platform UI scope in between"
    echo "    occurrence $count of this signature on this machine. Log it (tm-pr-workflow, \"Flake log\"): job \`local $p_context: $platform UI tests\`, step as the run printed it,"
    echo "    test and first error line as above, re-run: no (there is no retry; the next run passed); then scripts/ui-flake.sh --logged $id"
    return 0
}

cmd_pending() {
    [ -s "$PENDING" ] || { echo "ui-flake: no pending local UI flakes"; return 0; }
    awk -F '\t' '{ printf "%s: %s: %s\n    failed %s on %s (%s), passed %s on %s (%s); log it in CI_FLAKES.md, then scripts/ui-flake.sh --logged %s\n", $1, $2, $3, $5, substr($4, 1, 8), $6, $8, substr($7, 1, 8), $9, $1 }' "$PENDING"
}

cmd_pending_count() { if [ -s "$PENDING" ]; then wc -l < "$PENDING" | tr -d ' '; else echo 0; fi; }

cmd_logged() {
    local id="${1:-}" line
    [ -n "$id" ] || usage
    line="$(awk -F '\t' -v i="$id" '$1 == i {print; exit}' "$PENDING" 2>/dev/null)"
    [ -n "$line" ] || { echo "ui-flake: no pending flake $id" >&2; return 1; }
    printf '%s\n' "$line" >> "$LOGGED"
    awk -F '\t' -v i="$id" '$1 != i' "$PENDING" > "$PENDING.tmp.$$" && mv "$PENDING.tmp.$$" "$PENDING"
    echo "ui-flake: $id marked as logged"
}

self_test() {
    local tmp fails=0 out rc
    tmp="$(mktemp -d)" || return 1
    trap 'rm -rf "$tmp"' RETURN
    local repo="$tmp/repo"
    git init -q -b main "$repo"
    git -C "$repo" config user.email t@example.invalid; git -C "$repo" config user.name t
    mkdir -p "$repo/scripts" "$repo/androidApp" "$repo/iosApp" "$repo/docs"
    cp "$SELF" "$repo/scripts/ui-flake.sh"
    cp "$ROOT/scripts/classify-changes.sh" "$repo/scripts/classify-changes.sh"
    chmod +x "$repo"/scripts/*.sh
    echo base > "$repo/README.md"
    git -C "$repo" add -A && git -C "$repo" commit -q -m base
    export TM_UI_FLAKE_DIR="$tmp/flakes"
    local tool="$repo/scripts/ui-flake.sh"
    commit() { printf '%s\n' "$2" >> "$repo/$1"; git -C "$repo" add -A && git -C "$repo" commit -q -m "$1"; }
    sha() { git -C "$repo" rev-parse HEAD; }

    printf '%s\n' "11:05:01 /x/XCUIApplication+Scenario.swift:16: error: -[TrailMetricsUITests.DetailsDeleteTwiceUITests test_deleteConfirmedTwice_deletesOnce] : Failed to launch <XCUIApplicationImpl: 0x109806240 dev.roozbahani.TrailMetrics> via Xcode: Timed out while launching application via Xcode." "Test Case '-[TrailMetricsUITests.DetailsDeleteTwiceUITests test_deleteConfirmedTwice_deletesOnce]' failed (129.281 seconds)." > "$tmp/ios-fail.log"
    printf '%s\n' "dev.roozbahani.trailmetrics.ExternalStopIntentLeavesSessionTest > anExternalStopIntentLeavesTheLiveSessionAlone[TrailMetrics_UITest(AVD) - 17] FAILED " "	java.lang.AssertionError: MainActivity never came up. Expected value to be not null." > "$tmp/android-fail.log"
    printf '%s\n' "android-ui-tests: emulator-5560 is already attached; it is not started by this run" > "$tmp/env-fail.log"
    echo ok > "$tmp/pass.log"

    t() { # name wanted-fragment command... (the output must contain the fragment; "" means no flake line)
        local name="$1" frag="$2"
        shift 2
        out="$("$@" 2>&1)"
        if [ -z "$frag" ]; then
            if printf '%s' "$out" | grep -q "FLAKE"; then echo "FAIL $name: a flake was reported: $out"; fails=$((fails + 1)); else echo "ok   $name"; fi
        elif printf '%s' "$out" | grep -qF -- "$frag"; then echo "ok   $name"
        else echo "FAIL $name: wanted \"$frag\", got: $out"; fails=$((fails + 1)); fi
    }
    rec() { "$tool" --record --platform "$1" --result "$2" --log "$3" --context "${4:-gate}"; }

    t "a pass with no history records nothing" "" rec ios pass "$tmp/pass.log"
    t "an iOS failure is recorded with Class.test: message" "DetailsDeleteTwiceUITests.test_deleteConfirmedTwice_deletesOnce: Failed to launch <XCUIApplicationImpl: 0x.. dev.roozbahani.TrailMetrics>" rec ios fail "$tmp/ios-fail.log"
    t "the same commit passes: a flake" "FLAKE" rec ios pass "$tmp/pass.log"
    [ "$("$tool" --pending-count)" = 1 ] && echo "ok   one flake is pending" || { echo "FAIL pending count: $("$tool" --pending-count)"; fails=$((fails + 1)); }
    t "--pending names the platform and the signature" "ios: DetailsDeleteTwiceUITests.test_deleteConfirmedTwice_deletesOnce" "$tool" --pending
    t "a second pass is no flake" "" rec ios pass "$tmp/pass.log"
    id="$("$tool" --pending | head -n 1 | sed 's/:.*//')"
    t "--logged moves it out of the pending list" "marked as logged" "$tool" --logged "$id"
    [ "$("$tool" --pending-count)" = 0 ] && echo "ok   nothing is pending after --logged" || { echo "FAIL pending count after logged"; fails=$((fails + 1)); }
    t "--logged of an unknown id fails" "no pending flake" "$tool" --logged nonsense

    t "an Android failure signature has the class, test and assertion" "ExternalStopIntentLeavesSessionTest.anExternalStopIntentLeavesTheLiveSessionAlone: AssertionError: MainActivity never came up." rec android fail "$tmp/android-fail.log" main
    commit docs/a.md "docs only"
    t "a pass on a later commit with only docs changed: a flake (main, then gate)" "failed " rec android pass "$tmp/pass.log" gate
    out="$("$tool" --pending)"; printf '%s' "$out" | grep -qF "(main)" && echo "ok   the failure's context (main) is in the evidence" || { echo "FAIL context: $out"; fails=$((fails + 1)); }

    t "an environment failure has the last log line as its signature" "before any test: android-ui-tests: emulator-5560 is already attached" rec android fail "$tmp/env-fail.log"
    commit androidApp/X.kt "code"
    t "a pass after a change in the Android scope is not a flake" "not counted as a flake" rec android pass "$tmp/pass.log"
    t "an iOS failure, then an Android-only change, then an iOS pass: a flake" "FLAKE" sh -c "'$tool' --record --platform ios --result fail --log '$tmp/ios-fail.log' --context gate >/dev/null; printf 'y\n' >> '$repo/androidApp/Y.kt'; git -C '$repo' add -A; git -C '$repo' commit -q -m y; '$tool' --record --platform ios --result pass --log '$tmp/pass.log' --context gate"
    git -C "$repo" switch -q -c other HEAD~3
    mkdir -p "$repo/docs"
    commit docs/b.md "elsewhere"
    t "a failure on an unrelated history is not counted" "not on this commit's history" sh -c "'$tool' --record --platform ios --result fail --log '$tmp/ios-fail.log' --sha '$(git -C "$repo" rev-parse main)' --context gate >/dev/null; '$tool' --record --platform ios --result pass --log '$tmp/pass.log' --context gate"
    t "a usage error exits 2" "usage" sh -c "'$tool' --record --platform windows --result pass --log x --context gate 2>&1; test \$? -eq 2"
    if [ "$fails" -eq 0 ]; then echo "ui-flake self-test: all cases passed"; return 0; fi
    echo "ui-flake self-test: $fails case(s) failed" >&2
    return 1
}

case "${1:-}" in
    --record) shift; cmd_record "$@" ;;
    --pending) cmd_pending ;;
    --pending-count) cmd_pending_count ;;
    --logged) cmd_logged "${2:-}" ;;
    --self-test) self_test ;;
    *) usage ;;
esac
