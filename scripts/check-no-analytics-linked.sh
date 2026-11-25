#!/usr/bin/env bash
# No analytics or advertising-ID code in the apps. Crash reporting is Firebase Crashlytics without Google Analytics
# and without the advertising ID (owner decision 2026-11-25), but Firebase can pull both in without a code change:
# firebase-ios-sdk's Package.swift declares GoogleAppMeasurement and the on-device conversion SDK, so
# Package.resolved pins them, and a BoM or product change on Android can merge the AD_ID permission or the
# measurement components. This check fails when one of them is in the built app.
#
#   scripts/check-no-analytics-linked.sh --android [<merged manifest>]
#       default: the debug merged manifest that `./gradlew assembleDebug` writes
#   scripts/check-no-analytics-linked.sh --ios [<TrailMetrics.app>]
#       default: the Debug-iphonesimulator TrailMetrics.app of THIS checkout's DerivedData folder (the one whose
#       info.plist WorkspacePath is this checkout's iosApp/TrailMetrics.xcodeproj; another clone's never counts)
#   scripts/check-no-analytics-linked.sh --ios-text <symbols file> <links file>
#       the iOS rules on saved `nm` and `otool -L` output (the self-test uses it)
#   scripts/check-no-analytics-linked.sh --self-test
#
# Android fails on: the AD_ID permission, a com.google.android.gms.measurement or com.google.firebase.analytics
# component, the ads identifier provider. It also fails when the manifest is missing or is not this app's (no
# package dev.roozbahani.trailmetrics), so a check that read the wrong file does not pass.
# iOS fails on: a GoogleAppMeasurement, APMMeasurement, FIRAnalytics (the class, not FirebaseCore's
# FIRAnalyticsInterop protocols or FIRAnalyticsConfiguration), ASIdentifierManager or on-device conversion
# (ODC) symbol, or a link to AdSupport or AppTrackingTransparency. It also fails when the binary has no
# doInitKoinIos symbol (the Kotlin framework is linked into every app build), for the same reason, and when
# nm or otool fails on a binary that is there (exit 2: an unread binary is not a clean one).
# NM, OTOOL and DERIVED_DATA override the tools and the DerivedData directory (the self-test uses them).
# Where: the gate after assembleDebug and after the iOS build; CI's android-build and ios-build jobs.
# Exit: 0 clean, 1 a finding (each on its own line), 2 usage error or nothing to read. Bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_MANIFEST="$ROOT/androidApp/app/build/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml"

ANDROID_PATTERNS='com\.google\.android\.gms\.permission\.AD_ID|com\.google\.android\.gms\.measurement|com\.google\.firebase\.analytics|com\.google\.android\.gms\.ads\.identifier'
IOS_SYMBOL_PATTERNS='GoogleAppMeasurement|APMMeasurement|_OBJC_CLASS_\$_FIRAnalytics$|ASIdentifierManager|ODCConversion|_OBJC_CLASS_\$_ODC'
IOS_LINK_PATTERNS='AdSupport\.framework|AppTrackingTransparency\.framework'

check_android() {
    local manifest="$1"
    [ -f "$manifest" ] || { echo "no merged manifest at $manifest (run ./gradlew assembleDebug first)"; return 2; }
    if ! grep -q 'dev\.roozbahani\.trailmetrics' "$manifest"; then
        echo "$manifest is not the TrailMetrics app's merged manifest"
        return 2
    fi
    local found
    found="$(grep -n -o -E "$ANDROID_PATTERNS" "$manifest" | sort -u)"
    if [ -n "$found" ]; then
        echo "$found" | sed 's/^/analytics or advertising ID in the merged manifest: line /'
        return 1
    fi
    echo "android: no AD_ID permission, no measurement or analytics component ($manifest)"
    return 0
}

check_ios_text() {
    local symbols="$1" links="$2" status=0
    [ -f "$symbols" ] && [ -f "$links" ] || { echo "missing symbols or links file"; return 2; }
    if ! grep -q 'doInitKoinIos' "$symbols"; then
        echo "the symbols have no doInitKoinIos: not the TrailMetrics app binary"
        return 2
    fi
    local found
    found="$(grep -o -E "$IOS_SYMBOL_PATTERNS" "$symbols" | sort -u)"
    if [ -n "$found" ]; then
        echo "$found" | sed 's/^/analytics or advertising-ID symbol linked: /'
        status=1
    fi
    found="$(grep -o -E "$IOS_LINK_PATTERNS" "$links" | sort -u)"
    if [ -n "$found" ]; then
        echo "$found" | sed 's/^/advertising framework linked: /'
        status=1
    fi
    [ "$status" -eq 0 ] && echo "ios: no analytics or advertising-ID symbol, no AdSupport or AppTrackingTransparency link"
    return "$status"
}

# The DerivedData folder Xcode uses for this checkout: its info.plist names this checkout's project.
this_checkout_app() {
    local project="$ROOT/iosApp/TrailMetrics.xcodeproj" dir path
    for dir in "${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"/TrailMetrics-*; do
        [ -f "$dir/info.plist" ] || continue
        path="$(sed -n '/<key>WorkspacePath<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$dir/info.plist")"
        if [ "$path" = "$project" ]; then
            echo "$dir/Build/Products/Debug-iphonesimulator/TrailMetrics.app"
            return 0
        fi
    done
    return 1
}

check_ios() {
    local app="${1:-}"
    if [ -z "$app" ]; then
        app="$(this_checkout_app)" || { echo "no DerivedData folder of this checkout ($ROOT/iosApp/TrailMetrics.xcodeproj)"; return 2; }
    fi
    [ -n "$app" ] && [ -d "$app" ] || { echo "no built TrailMetrics.app at $app (run the iOS build first)"; return 2; }
    local tmp bin read=0
    tmp="$(mktemp -d)" || return 2
    : > "$tmp/symbols"; : > "$tmp/links"
    # A Debug build puts the code in TrailMetrics.debug.dylib; a Release build in the executable.
    for bin in "$app/TrailMetrics" "$app/TrailMetrics.debug.dylib"; do
        [ -f "$bin" ] || continue
        if ! "${NM:-nm}" "$bin" >> "$tmp/symbols" 2>/dev/null || ! "${OTOOL:-otool}" -L "$bin" >> "$tmp/links" 2>/dev/null; then
            echo "could not read $bin with nm and otool -L"
            rm -rf "$tmp"
            return 2
        fi
        read=$((read + 1))
    done
    [ "$read" -gt 0 ] || { rm -rf "$tmp"; echo "no binary in $app"; return 2; }
    check_ios_text "$tmp/symbols" "$tmp/links"
    local status=$?
    rm -rf "$tmp"
    [ "$status" -eq 0 ] && echo "ios: read $app"
    return "$status"
}

self_test() {
    local dir fails=0
    dir="$(mktemp -d)" || exit 2
    t() { # <name> <expected exit> <command...>
        local name="$1" want="$2"; shift 2
        "$@" > "$dir/out" 2>&1
        local got=$?
        if [ "$got" -eq "$want" ]; then echo "ok    $name"; else echo "FAIL  $name (exit $got, want $want)"; sed 's/^/      /' "$dir/out"; fails=$((fails + 1)); fi
    }
    local app='<manifest package="dev.roozbahani.trailmetrics"><application/></manifest>'
    echo "$app" > "$dir/clean.xml"
    printf '%s\n' '<manifest package="dev.roozbahani.trailmetrics">' \
        '<uses-permission android:name="com.google.android.gms.permission.AD_ID"/></manifest>' > "$dir/adid.xml"
    printf '%s\n' '<manifest package="dev.roozbahani.trailmetrics"><application>' \
        '<receiver android:name="com.google.android.gms.measurement.AppMeasurementReceiver"/></application></manifest>' > "$dir/measurement.xml"
    echo '<manifest package="com.other.app"/>' > "$dir/other.xml"
    t "android: a clean manifest passes" 0 check_android "$dir/clean.xml"
    t "android: the AD_ID permission fails" 1 check_android "$dir/adid.xml"
    t "android: a measurement component fails" 1 check_android "$dir/measurement.xml"
    t "android: another app's manifest is not read as clean" 2 check_android "$dir/other.xml"
    t "android: a missing manifest is not read as clean" 2 check_android "$dir/missing.xml"

    printf '%s\n' '0000 T _kfun:dev.roozbahani.trailmetrics.shared.di#doInitKoinIos(){}' \
        '0000 S _OBJC_CLASS_$_FIRCLSFileManager' '0000 S _OBJC_CLASS_$_FIRAnalyticsConfiguration' \
        '0000 S __OBJC_PROTOCOL_$_FIRAnalyticsInterop' > "$dir/clean.sym"
    printf '%s\n' "$(cat "$dir/clean.sym")" '0000 S _OBJC_CLASS_$_APMMeasurement' > "$dir/apm.sym"
    printf '%s\n' "$(cat "$dir/clean.sym")" '0000 S _OBJC_CLASS_$_FIRAnalytics' > "$dir/firanalytics.sym"
    printf '%s\n' '0000 S _OBJC_CLASS_$_FIRCLSFileManager' > "$dir/notapp.sym"
    echo '	/usr/lib/libobjc.A.dylib (compatibility version 1.0.0)' > "$dir/clean.links"
    printf '%s\n' "$(cat "$dir/clean.links")" '	/System/Library/Frameworks/AdSupport.framework/AdSupport' > "$dir/adsupport.links"
    t "ios: FirebaseCore's analytics interop and configuration pass" 0 check_ios_text "$dir/clean.sym" "$dir/clean.links"
    t "ios: an APMMeasurement symbol fails" 1 check_ios_text "$dir/apm.sym" "$dir/clean.links"
    t "ios: the FIRAnalytics class fails" 1 check_ios_text "$dir/firanalytics.sym" "$dir/clean.links"
    t "ios: an AdSupport link fails" 1 check_ios_text "$dir/clean.sym" "$dir/adsupport.links"
    t "ios: a binary without the Kotlin framework is not read as clean" 2 check_ios_text "$dir/notapp.sym" "$dir/clean.links"

    # The app of this checkout, among DerivedData folders of other clones, with fake nm and otool.
    local dd="$dir/DerivedData" other mine
    other="$dd/TrailMetrics-other"; mine="$dd/TrailMetrics-mine"
    mkdir -p "$other/Build/Products/Debug-iphonesimulator/TrailMetrics.app" "$mine/Build/Products/Debug-iphonesimulator/TrailMetrics.app"
    plist() { printf '<?xml version="1.0"?>\n<plist version="1.0">\n<dict>\n\t<key>WorkspacePath</key>\n\t<string>%s</string>\n</dict>\n</plist>\n' "$1"; }
    plist "/elsewhere/TrailMetrics/iosApp/TrailMetrics.xcodeproj" > "$other/info.plist"
    plist "$ROOT/iosApp/TrailMetrics.xcodeproj" > "$mine/info.plist"
    echo mine > "$mine/Build/Products/Debug-iphonesimulator/TrailMetrics.app/TrailMetrics.debug.dylib"
    echo other > "$other/Build/Products/Debug-iphonesimulator/TrailMetrics.app/TrailMetrics.debug.dylib"
    # fake nm: the clean symbols for this checkout's binary, an analytics symbol for the other clone's.
    printf '#!/bin/sh\nif grep -q mine "$1"; then cat %s; else cat %s; fi\n' "$dir/clean.sym" "$dir/apm.sym" > "$dir/nm"
    printf '#!/bin/sh\ncat %s\n' "$dir/clean.links" > "$dir/otool"
    printf '#!/bin/sh\nexit 1\n' > "$dir/failing"
    chmod +x "$dir/nm" "$dir/otool" "$dir/failing"
    t "ios: reads this checkout's app, not another clone's newer one" 0 env DERIVED_DATA="$dd" NM="$dir/nm" OTOOL="$dir/otool" "$0" --ios
    t "ios: a failing nm is not read as clean" 2 env DERIVED_DATA="$dd" NM="$dir/failing" OTOOL="$dir/otool" "$0" --ios
    t "ios: a failing otool is not read as clean" 2 env DERIVED_DATA="$dd" NM="$dir/nm" OTOOL="$dir/failing" "$0" --ios
    rm -rf "$mine"
    t "ios: no DerivedData folder of this checkout is not read as clean" 2 env DERIVED_DATA="$dd" NM="$dir/nm" OTOOL="$dir/otool" "$0" --ios
    rm -rf "$dir"
    [ "$fails" -eq 0 ] && { echo "check-no-analytics-linked self-test: all passed"; exit 0; }
    echo "check-no-analytics-linked self-test: $fails failed"
    exit 1
}

case "${1:-}" in
    --android) check_android "${2:-$DEFAULT_MANIFEST}"; exit $? ;;
    --ios) check_ios "${2:-}"; exit $? ;;
    --ios-text) [ $# -eq 3 ] || { echo "usage: --ios-text <symbols> <links>"; exit 2; }; check_ios_text "$2" "$3"; exit $? ;;
    --self-test) self_test ;;
    *) sed -n '2,24p' "$0"; exit 2 ;;
esac
