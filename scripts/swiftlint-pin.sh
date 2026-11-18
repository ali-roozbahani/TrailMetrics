#!/usr/bin/env bash
# The pinned SwiftLint version, in one file (config/swiftlint.pin: version and the sha256 of the release's
# portable_swiftlint.zip), read by the gate and by CI so that the same code passes or fails in both.
#
#   scripts/swiftlint-pin.sh --version          print the pinned version
#   scripts/swiftlint-pin.sh --check            fail (exit 1) when `swiftlint` on PATH is not that version, with the
#                                               command that installs it; exit 2 when there is no swiftlint
#   scripts/swiftlint-pin.sh --install <dir>    download the pinned release, check its sha256, put `swiftlint` in <dir>
#                                               (CI: then add <dir> to PATH; locally: put <dir> first on PATH)
#   scripts/swiftlint-pin.sh --self-test
#
# SWIFTLINT_PIN_FILE and SWIFTLINT_PIN_URL replace the pin file and the download URL (the self-test uses them).
# Exit: 0 ok, 1 a mismatch or a failed download or checksum, 2 usage error or no swiftlint. bash 3.2 compatible.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN_FILE="${SWIFTLINT_PIN_FILE:-$ROOT/config/swiftlint.pin}"
USAGE="usage: scripts/swiftlint-pin.sh --version | --check | --install <dir> | --self-test"

pin() { # <key>
    sed -n "s/^$1=//p" "$PIN_FILE" | head -1
}

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

do_install() { # <dir>
    local version sha url tmp got
    version="$(pin version)"; sha="$(pin sha256)"
    if [ -z "$version" ] || [ -z "$sha" ]; then echo "swiftlint-pin: $PIN_FILE has no version or sha256" >&2; return 1; fi
    url="${SWIFTLINT_PIN_URL:-https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip}"
    tmp="$(mktemp -d)"
    if ! curl -fsSL -o "$tmp/portable.zip" "$url"; then echo "swiftlint-pin: download of $url failed" >&2; rm -rf "$tmp"; return 1; fi
    got="$(sha256_of "$tmp/portable.zip")"
    if [ "$got" != "$sha" ]; then
        echo "swiftlint-pin: sha256 of the download is $got, the pin says $sha: not installed" >&2
        rm -rf "$tmp"; return 1
    fi
    mkdir -p "$1" && unzip -q -o "$tmp/portable.zip" swiftlint -d "$1" && chmod +x "$1/swiftlint"
    local rc=$?
    rm -rf "$tmp"
    [ $rc = 0 ] && echo "swiftlint-pin: installed SwiftLint $version in $1"
    return $rc
}

do_check() {
    local want have
    want="$(pin version)"
    if [ -z "$want" ]; then echo "swiftlint-pin: $PIN_FILE has no version" >&2; return 1; fi
    if ! command -v swiftlint >/dev/null 2>&1; then
        echo "swiftlint is not installed; the pinned version is $want: scripts/swiftlint-pin.sh --install <dir>, then put <dir> first on PATH" >&2
        return 2
    fi
    have="$(swiftlint version 2>/dev/null | head -1)"
    if [ "$have" != "$want" ]; then
        echo "swiftlint $have is installed, the pinned version is $want (config/swiftlint.pin): CI lints with $want, so the same code could pass here and fail there." >&2
        echo "Install it: scripts/swiftlint-pin.sh --install <dir>, then put <dir> first on PATH (brew installs only the newest release)." >&2
        return 1
    fi
    echo "swiftlint $have matches the pin"
}

self_test() {
    local failed=0 rc
    w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
    expect() { if [ "$2" = "$3" ]; then echo "ok   $1: $2"; else echo "FAIL $1: expected $3, got $2"; failed=1; fi; }
    # a fake swiftlint of a chosen version
    mkdir -p "$w/bin"; printf '#!/bin/sh\necho "${FAKE_VERSION:-1.2.3}"\n' > "$w/bin/swiftlint"; chmod +x "$w/bin/swiftlint"
    printf 'version=1.2.3\nsha256=0\n' > "$w/pin"
    export SWIFTLINT_PIN_FILE="$w/pin"
    expect "--version" "$("$0" --version)" 1.2.3
    PATH="$w/bin:$PATH" FAKE_VERSION=1.2.3 "$0" --check >/dev/null 2>&1; expect "check, same version" $? 0
    PATH="$w/bin:$PATH" FAKE_VERSION=1.2.4 "$0" --check >"$w/out" 2>&1; rc=$?; expect "check, other version" $rc 1
    grep -q "pinned version is 1.2.3" "$w/out" && echo "ok   mismatch message names the pin" || { echo "FAIL mismatch message"; failed=1; }
    PATH="/usr/bin:/bin" "$0" --check >/dev/null 2>&1; expect "check, no swiftlint" $? 2
    # install: a fake release asset served from a file
    mkdir -p "$w/zip" && printf '#!/bin/sh\necho 1.2.3\n' > "$w/zip/swiftlint" && (cd "$w/zip" && zip -q ../asset.zip swiftlint)
    printf 'version=1.2.3\nsha256=%s\n' "$(sha256_of "$w/asset.zip")" > "$w/pin"
    SWIFTLINT_PIN_URL="file://$w/asset.zip" "$0" --install "$w/out-dir" >/dev/null 2>&1; expect "install, right sha256" $? 0
    [ -x "$w/out-dir/swiftlint" ] && echo "ok   installed binary is executable" || { echo "FAIL no executable in out-dir"; failed=1; }
    printf 'version=1.2.3\nsha256=deadbeef\n' > "$w/pin"
    SWIFTLINT_PIN_URL="file://$w/asset.zip" "$0" --install "$w/out-dir2" >/dev/null 2>&1; expect "install, wrong sha256" $? 1
    [ ! -e "$w/out-dir2/swiftlint" ] && echo "ok   nothing installed on a wrong sha256" || { echo "FAIL installed despite a wrong sha256"; failed=1; }
    [ "$failed" = 0 ] && echo "swiftlint pin: self-test passed" || echo "swiftlint pin: self-test FAILED"
    return "$failed"
}

case "${1:-}" in
    --version) [ $# -eq 1 ] || { echo "$USAGE" >&2; exit 2; }; pin version ;;
    --check) [ $# -eq 1 ] || { echo "$USAGE" >&2; exit 2; }; do_check ;;
    --install) [ $# -eq 2 ] || { echo "$USAGE" >&2; exit 2; }; do_install "$2" ;;
    --self-test) [ $# -eq 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    *) echo "$USAGE" >&2; exit 2 ;;
esac
