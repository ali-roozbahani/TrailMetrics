#!/bin/sh
# Production framework check: no test-only Kotlin may be in the production TrailMetricsShared
# framework. The Swift test support (SwiftTestFlow, SwiftFailingTestFlow, SwiftTestScope,
# SwiftTestResult, package ...testsupport) lives in :shared-uitest and reaches only the test-only
# variant of the framework (ADR-002, "Amendment"). The gate (step "Production framework check",
# right after the production build) and CI's ios-main job run this on the framework that
# scripts/build-kmp-framework.sh builds for every normal build.
#
#   scripts/check-production-framework.sh [<xcframework>]   default: the debug path SharedKit links
#   scripts/check-production-framework.sh --self-test       fake frameworks in a scratch directory
#
# Runs `strings -a` on the binary of every slice and fails (exit 1, messages on stdout) when one
# of the names below occurs in it. It also fails when a slice has no binary or the binary does not
# contain KoinHelper (a production symbol): a check that read the wrong or an empty file would
# otherwise pass. Exit 2 for a usage error. POSIX sh and strings only.
set -eu

FORBIDDEN="SwiftTestFlow SwiftFailingTestFlow SwiftTestScope SwiftTestResult testsupport"
DEFAULT_XCFRAMEWORK="shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework"

usage() {
  echo "error: $1" >&2
  echo "usage: scripts/check-production-framework.sh [<xcframework>]" >&2
  echo "       scripts/check-production-framework.sh --self-test" >&2
  exit 2
}

check_framework() {
  xcframework="$1"
  status=0
  slices=0
  for binary in "$xcframework"/*/TrailMetricsShared.framework/TrailMetricsShared; do
    slice="$(basename "$(dirname "$(dirname "$binary")")")"
    if [ ! -f "$binary" ]; then
      echo "error: production framework check: no binary at $xcframework/*/TrailMetricsShared.framework"
      return 1
    fi
    slices=$((slices + 1))
    symbols="$(mktemp)"
    strings -a "$binary" > "$symbols"
    if ! grep -q KoinHelper "$symbols"; then
      echo "error: production framework check: $slice has no KoinHelper, so this is not the production framework"
      status=1
    fi
    for name in $FORBIDDEN; do
      count="$(grep -c "$name" "$symbols" || true)"
      echo "$slice $name: $count"
      if [ "$count" -ne 0 ]; then
        status=1
      fi
    done
    rm -f "$symbols"
  done
  if [ "$slices" -ne 2 ]; then
    echo "error: production framework check: expected 2 slices (ios-arm64, ios-arm64-simulator), found $slices"
    return 1
  fi
  if [ "$status" -ne 0 ]; then
    echo "error: production framework check: test-only Kotlin is in the production framework" \
      "(or the framework is not the production one)"
    return 1
  fi
  echo "Production framework check: none of $FORBIDDEN is in the production framework ($slices slices)."
}

self_test() {
  check="$1"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  failed=0
  total=0
  # name | production contents of the simulator slice | expected result
  run_case() {
    name="$1"; simulator_text="$2"; expected="$3"
    total=$((total + 1))
    rm -rf "$work/fw"
    for slice in ios-arm64 ios-arm64-simulator; do
      mkdir -p "$work/fw/$slice/TrailMetricsShared.framework"
      printf 'padding\nTMSKoinHelper\n' > "$work/fw/$slice/TrailMetricsShared.framework/TrailMetricsShared"
    done
    printf '%s\n' "$simulator_text" >> "$work/fw/ios-arm64-simulator/TrailMetricsShared.framework/TrailMetricsShared"
    if sh "$check" "$work/fw" > "$work/out" 2>&1; then actual=pass; else actual=fail; fi
    if [ "$actual" = "$expected" ]; then
      echo "ok   $name ($actual)"
    else
      failed=$((failed + 1))
      echo "FAIL $name: expected $expected, got $actual"
      sed 's/^/    /' "$work/out"
    fi
  }
  run_case "clean production framework" "TMSSomeOtherClass" pass
  run_case "SwiftTestFlow present" "TMSSwiftTestFlow" fail
  run_case "SwiftFailingTestFlow present" "TMSSwiftFailingTestFlow" fail
  run_case "SwiftTestScope present" "kfun:dev.roozbahani.SwiftTestScope" fail
  run_case "SwiftTestResult present" "SwiftTestResult" fail
  run_case "testsupport package present" "dev.roozbahani.trailmetrics.uitest.testsupport" fail
  rm -rf "$work/fw"
  total=$((total + 1))
  if sh "$check" "$work/fw" > "$work/out" 2>&1; then
    failed=$((failed + 1)); echo "FAIL missing framework: expected fail, got pass"
  else
    echo "ok   missing framework (fail)"
  fi
  mkdir -p "$work/fw/ios-arm64/TrailMetricsShared.framework" "$work/fw/ios-arm64-simulator/TrailMetricsShared.framework"
  : > "$work/fw/ios-arm64/TrailMetricsShared.framework/TrailMetricsShared"
  : > "$work/fw/ios-arm64-simulator/TrailMetricsShared.framework/TrailMetricsShared"
  total=$((total + 1))
  if sh "$check" "$work/fw" > "$work/out" 2>&1; then
    failed=$((failed + 1)); echo "FAIL empty binaries: expected fail, got pass"
  else
    echo "ok   empty binaries (fail)"
  fi
  if [ "$failed" -ne 0 ]; then
    echo "check-production-framework self-test: FAILED, $failed of $total cases"
    return 1
  fi
  echo "check-production-framework self-test: $total/$total cases passed"
}

if [ $# -ge 1 ] && [ "$1" = --self-test ]; then
  [ $# -eq 1 ] || usage "--self-test takes no argument"
  self_test "$0"
  exit $?
fi
[ $# -le 1 ] || usage "expected at most one XCFramework path"
xcframework="${1:-$DEFAULT_XCFRAMEWORK}"
[ -d "$xcframework" ] || usage "not a directory: $xcframework"
check_framework "$xcframework"
