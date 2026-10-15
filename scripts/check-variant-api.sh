#!/bin/sh
# API check of the test-only framework variant (ADR-002, "Amendment"; docs/epics/ios-ui-tests.md,
# D1 and F12): the uitest variant of TrailMetricsShared.xcframework, built by :shared-uitest, must
# have the production framework's API plus the declarations of the UI-test seam, and nothing else.
# scripts/build-kmp-framework.sh runs it after building the variant and before copying it over the
# production framework's debug path; the gate runs its self-test.
#
#   scripts/check-variant-api.sh <production.xcframework> <variant.xcframework>
#   scripts/check-variant-api.sh --self-test                  the fixtures in
#                                                             scripts/check-variant-api-fixtures/
#   scripts/check-variant-api.sh --self-test --check <file>   the same fixtures against another
#                                                             copy of the check (to show a case
#                                                             going red on an older version)
#
# Exit 0 when the API matches, 1 when it does not (messages on stdout), 2 for a usage error.
# POSIX sh, sed and awk only, like scripts/build-kmp-framework.sh, which held this check before.
#
# Compared per slice: the Objective-C headers and every Swift interface of the framework. Each file
# is normalised, then compared as a sorted list of lines (the variant orders some declarations
# differently):
#   - SKIE's per-build counters, only in the names `Skie_Suspend__<n>__...` and
#     `Skie__TypeDef__<n>__...`, become `__N__`.
#   - The `cancel` label swap (docs/epics/ios-ui-tests.md, F12): the variant gives the Swift
#     labels `cancel(cause:)` and `cancel(cause_:)` of Ktor's ByteReadChannel/ByteWriteChannel
#     (a Throwable) and coroutines' Job (a CancellationException) the other way round. Another
#     `export(...)` order did not remove it, so exactly these method lines lose their label:
#     the `cancelCause` line with a Throwable in the protocols TMSKtor_ioByteReadChannel and
#     TMSKtor_ioByteWriteChannel, and the one with a CancellationException in
#     TMSKotlinx_coroutines_coreJob. Every other `cancel` keeps its label.
#   - Variant only: the seam's declarations, exactly the names in SEAM_NAMES below, are left out:
#     an Objective-C `@interface` block of one of those classes (not a category on it), a
#     top-level Swift declaration or extension of one of those names, and those names on the
#     `@class` forward declaration line. Any other declaration fails, whether or not its name
#     contains UiTest. An extension's name is compared without its module qualifier, in either
#     form the Swift interface writes it: `TrailMetricsShared::` (Xcode 27, Swift 6.4) or
#     `TrailMetricsShared.` (Xcode 26.6, CI). No other module's qualifier is stripped.
#   - Blank lines are dropped (the left-out declarations leave theirs behind).
# Anything else that differs fails. Production must contain no UiTest name at all.

# The seam: the only names that may exist in the variant alone, as they are declared in the
# variant's headers and Swift interfaces (taken from a real build of :shared-uitest).
#   Swift name               where it is declared
#   doInitKoinIosForUiTest   Swift interface: `public func doInitKoinIosForUiTest(scenario:)`;
#                            Objective-C: a method of TMSUiTestEntryKt
#   UiTestScenario           Swift interface: SKIE's `enum UiTestScenario` and its extensions;
#                            Objective-C: TMSUiTestScenario, which SKIE names __UiTestScenario in
#                            Swift (the Swift interface extends it under that name)
#   UiTestControls           Objective-C: TMSUiTestControls
#   UiTestEntryKt            Objective-C: TMSUiTestEntryKt, the file class of
#                            doInitKoinIosForUiTest
SEAM_NAMES="doInitKoinIosForUiTest UiTestScenario __UiTestScenario TMSUiTestScenario TMSUiTestControls TMSUiTestEntryKt"

set -eu
API_DIR=""
work=""
trap '[ -z "$API_DIR" ] || rm -rf "$API_DIR"; [ -z "$work" ] || rm -rf "$work"' EXIT

usage() {
  echo "error: $1" >&2
  echo "usage: scripts/check-variant-api.sh <production.xcframework> <variant.xcframework>" >&2
  echo "       scripts/check-variant-api.sh --self-test [--check <file>]" >&2
  exit 2
}

normalise_api() {
  sed -E \
    -e 's/(Skie_Suspend|Skie__TypeDef)__[0-9]+__/\1__N__/g' \
    "$1" \
  | awk -v kind="$2" -v seam_names="$SEAM_NAMES" '
      BEGIN { n_seam = split(seam_names, seam_list, " "); for (i = 1; i <= n_seam; i++) seam[seam_list[i]] = 1 }
      function flush(   i) { for (i = 1; i <= n; i++) print buf[i]; n = 0 }
      kind == "h" {
        if (inblock) {
          if (cancel_type != "" && $0 ~ /^- \(void\)cancelCause_?:\(TMSKotlin[A-Za-z]+ \* _Nullable\)cause __attribute__\(\(swift_name\("cancel\(cause_?:\)"\)\)\);$/ &&
              index($0, "(" cancel_type " * _Nullable)") > 0) {
            sub(/cancelCause_?:/, "cancelCause<label>:")
            sub(/cancel\(cause_?:\)/, "cancel(cause<label>:)")
          }
          buf[++n] = $0
          if ($0 == "@end") { if (!drop) flush(); n = 0; inblock = 0 }
          next
        }
        if ($0 ~ /^@class .*;$/) {
          k = split(substr($0, 8, length($0) - 8), names, ", "); line = ""
          for (i = 1; i <= k; i++) if (!(names[i] in seam)) line = line (line == "" ? "" : ", ") names[i]
          $0 = "@class " line ";"
        }
        if ($0 ~ /^@(interface|protocol) / && $0 !~ /;$/) {
          buf[++n] = $0; inblock = 1; drop = (($2 in seam) && $0 !~ /^@interface [A-Za-z0-9_]+ \(/)
          cancel_type = ""
          if ($0 ~ /^@protocol TMSKtor_io(ByteReadChannel|ByteWriteChannel)( |$)/) cancel_type = "TMSKotlinThrowable"
          if ($0 ~ /^@protocol TMSKotlinx_coroutines_coreJob( |$)/) cancel_type = "TMSKotlinCancellationException"
          next
        }
        if ($0 == "") { flush(); print; next }
        buf[++n] = $0
        next
      }
      kind == "swift" {
        if (inblock) { if (!drop) print; if ($0 == "}") inblock = 0; next }
        if ($0 ~ /^@[A-Za-z_]+(\(.*\))?$/) { buf[++n] = $0; next }
        if ($0 ~ /^[^ }]/) {
          name = ""
          if (match($0, /^extension [A-Za-z0-9_:.]+/)) {
            name = substr($0, 11, RLENGTH - 10); sub(/^TrailMetricsShared(::|\.)/, "", name)
          } else if (match($0, /(^| )(func|enum|class|struct|protocol|typealias|var|let) [A-Za-z0-9_]+/)) {
            name = substr($0, RSTART, RLENGTH); sub(/^.* /, "", name)
          }
          drop = (name in seam)
          if (drop) n = 0; else { flush(); print }
          if ($0 ~ /\{$/) inblock = 1
          next
        }
        flush(); print
      }
      END { flush() }' \
  | awk 'NF' \
  | LC_ALL=C sort
}

check_variant_api() {
  production="$1"
  variant="$2"
  API_DIR="$(mktemp -d)"
  status=0
  slices=0
  for production_framework in "$production"/*/TrailMetricsShared.framework; do
    slice="$(basename "$(dirname "$production_framework")")"
    variant_framework="$variant/$slice/TrailMetricsShared.framework"
    slices=$((slices + 1))
    for file in "$production_framework"/Headers/TrailMetricsShared.h \
        "$production_framework"/Headers/TrailMetricsShared-Swift.h \
        "$production_framework"/Modules/TrailMetricsShared.swiftmodule/*.swiftinterface; do
      relative="${file#"$production_framework"/}"
      case "$relative" in
        *.h) kind=h ;;
        *) kind=swift ;;
      esac
      if [ ! -f "$file" ] || [ ! -f "$variant_framework/$relative" ]; then
        echo "error: API check: $slice/$relative is missing in the production or the uitest framework"
        status=1
        continue
      fi
      if grep -q UiTest "$file"; then
        echo "error: API check: the production framework's $slice/$relative contains UiTest declarations"
        status=1
      fi
      normalise_api "$file" "$kind" > "$API_DIR/production"
      normalise_api "$variant_framework/$relative" "$kind" > "$API_DIR/variant"
      if [ ! -s "$API_DIR/production" ] || [ ! -s "$API_DIR/variant" ]; then
        echo "error: API check: $slice/$relative normalised to nothing"
        status=1
        continue
      fi
      if ! diff "$API_DIR/production" "$API_DIR/variant" > "$API_DIR/diff"; then
        echo "error: API check: $slice/$relative of the uitest variant differs from production beyond" \
          "the seam's declarations (< production only, > uitest variant only):"
        head -n 40 "$API_DIR/diff"
        status=1
      fi
    done
    if ! grep -q 'doInitKoinIosForUiTest' "$variant_framework/Headers/TrailMetricsShared.h" 2>/dev/null; then
      echo "error: API check: the uitest framework's $slice has no doInitKoinIosForUiTest"
      status=1
    fi
  done
  variant_slices=0
  for variant_framework in "$variant"/*/TrailMetricsShared.framework; do
    [ ! -d "$variant_framework" ] || variant_slices=$((variant_slices + 1))
  done
  # Both slices, or one and the same slice in both (a simulator-only build, see
  # scripts/build-kmp-framework.sh): the loop above already failed a slice missing in the variant.
  if [ "$slices" -lt 1 ] || [ "$slices" -gt 2 ] || [ "$variant_slices" -ne "$slices" ]; then
    echo "error: API check: expected 2 slices (ios-arm64, ios-arm64-simulator) in both frameworks," \
      "or one and the same slice in both when built simulator-only"
    status=1
  fi
  if [ "$status" -ne 0 ]; then
    return 1
  fi
  echo "API check: the uitest variant has production's API plus the seam's declarations only" \
    "($slices slices)."
}

# Each directory in scripts/check-variant-api-fixtures/cases/ is one case. The self-test builds a
# production and a variant framework directory from it, with the slices ios-arm64 and
# ios-arm64-simulator (or the ones listed in `slices-production` / `slices-variant`), each slice
# holding Headers/TrailMetricsShared.h, Headers/TrailMetricsShared-Swift.h and one
# Modules/TrailMetricsShared.swiftmodule/<slice>.swiftinterface. A file comes from the case's
# `production/` or `variant/` directory, else from `base/production/` or `base/variant/` (the
# seam on top of a small production API, which passes). `expect` holds `result: pass` or
# `result: fail`, and `output: <text>` lines that the check's output must contain.
self_test() {
  check="$1"
  fixtures="$(cd "$(dirname "$0")" && pwd)/check-variant-api-fixtures"
  if [ ! -d "$fixtures/cases" ] || [ ! -d "$fixtures/base" ]; then
    echo "check-variant-api self-test: FAILED, no fixtures in $fixtures" >&2
    return 1
  fi
  work="$(mktemp -d)"
  total=0
  failed=0
  for case_dir in "$fixtures"/cases/*/; do
    case_dir="${case_dir%/}"
    name="$(basename "$case_dir")"
    total=$((total + 1))
    rm -rf "$work/production" "$work/variant"
    for side in production variant; do
      slices="ios-arm64 ios-arm64-simulator"
      if [ -f "$case_dir/slices-$side" ]; then
        slices="$(cat "$case_dir/slices-$side")"
      fi
      mkdir -p "$work/$side"
      for slice in $slices; do
        framework="$work/$side/$slice/TrailMetricsShared.framework"
        mkdir -p "$framework/Headers" "$framework/Modules/TrailMetricsShared.swiftmodule"
        for file in TrailMetricsShared.h TrailMetricsShared-Swift.h TrailMetricsShared.swiftinterface; do
          source="$case_dir/$side/$file"
          [ -f "$source" ] || source="$fixtures/base/$side/$file"
          case "$file" in
            *.swiftinterface) target="$framework/Modules/TrailMetricsShared.swiftmodule/$slice.swiftinterface" ;;
            *) target="$framework/Headers/$file" ;;
          esac
          cp "$source" "$target"
        done
      done
    done
    expected="$(sed -n 's/^result: //p' "$case_dir/expect")"
    if sh "$check" "$work/production" "$work/variant" > "$work/out" 2>&1; then
      actual=pass
    else
      code=$?
      actual=fail
      [ "$code" -eq 1 ] || actual="error (exit $code)"
    fi
    problem=""
    if [ "$actual" != "$expected" ]; then
      problem="expected $expected, got $actual"
    else
      while IFS= read -r line; do
        case "$line" in
          "output: "*)
            if ! grep -qF -- "${line#output: }" "$work/out"; then
              problem="output lacks: ${line#output: }"
              break
            fi
            ;;
        esac
      done < "$case_dir/expect"
    fi
    if [ -n "$problem" ]; then
      failed=$((failed + 1))
      echo "FAIL $name: $problem"
      sed 's/^/    /' "$work/out"
    else
      echo "ok   $name ($actual)"
    fi
  done
  if [ "$failed" -ne 0 ]; then
    echo "check-variant-api self-test: FAILED, $failed of $total cases"
    return 1
  fi
  echo "check-variant-api self-test: $total/$total cases passed"
}

if [ $# -ge 1 ] && [ "$1" = --self-test ]; then
  shift
  check="$0"
  if [ $# -gt 0 ]; then
    [ $# -eq 2 ] && [ "$1" = --check ] || usage "--self-test takes only --check <file>"
    [ -f "$2" ] || usage "no such file: $2"
    check="$2"
  fi
  self_test "$check"
  exit $?
fi
[ $# -eq 2 ] || usage "expected the production and the variant XCFramework paths"
[ -d "$1" ] || usage "not a directory: $1"
[ -d "$2" ] || usage "not a directory: $2"
check_variant_api "$1" "$2"
