#!/bin/sh
# Builds the debug TrailMetricsShared.xcframework that iosApp/Packages/SharedKit links, but only
# when one of its inputs changed since the last successful build, or the other variant is in
# place. The single entry point for that framework outside CI: the TrailMetrics scheme's Build
# pre-action, the app target's "Build KMP Shared Framework" phase and scripts/pre-push-check.sh
# all call this script.
#
# Usage: scripts/build-kmp-framework.sh [--build-phase] [--variant production|uitest]
#   --build-phase  Called from inside the Xcode build. By then Xcode has already copied the
#                  XCFramework and compiled the Swift packages against it, so a rebuild here is
#                  too late for this build: rebuild, then fail with an error asking for another
#                  build instead of linking the stale copy. Normally the scheme pre-action has
#                  already built it (a failing pre-action fails the build) and this mode only
#                  checks the hash. It fires when the pre-action didn't run at all.
#   --variant      Which framework to put at the debug path. Without it: uitest when Xcode's
#                  CONFIGURATION is Debug-UITest (pre-action and --build-phase alike), production
#                  otherwise. The gate and CI, which run outside Xcode, pass --variant uitest.
#
# Variants (ADR-002, "Amendment"):
#   production  :shared's framework, what every normal Debug and Release build links.
#   uitest      The test-only variant built by :shared-uitest: the same Swift module with the
#               same API plus the UI-test seam (package dev.roozbahani.trailmetrics.uitest). It
#               is copied over the production framework's debug path, so SharedKit/Package.swift
#               stays as it is, and only after its API passed the check below.
# The stamp records the variant next to the input hash, so switching from one variant to the
# other always rebuilds and copies, and a normal build never links a variant left behind.
set -eu
cd "$(dirname "$0")/.."

usage() {
  echo "error: $1" >&2
  echo "usage: scripts/build-kmp-framework.sh [--build-phase] [--variant production|uitest]" >&2
  exit 2
}

BUILD_PHASE=false
VARIANT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build-phase)
      BUILD_PHASE=true
      ;;
    --variant)
      [ $# -ge 2 ] || usage "--variant needs a value"
      [ -z "$VARIANT" ] || usage "--variant given twice"
      case "$2" in
        production|uitest) VARIANT="$2" ;;
        *) usage "unknown variant '$2'" ;;
      esac
      shift
      ;;
    *)
      usage "unknown argument '$1'"
      ;;
  esac
  shift
done
if [ -z "$VARIANT" ]; then
  if [ "${CONFIGURATION:-}" = "Debug-UITest" ]; then
    VARIANT=uitest
  else
    VARIANT=production
  fi
fi

# The hash covers everything that changes the framework's content: Kotlin sources of the four
# exported modules and of shared-uitest (both variants hash the same inputs; the stamp's variant
# is what tells them apart), their build files, settings, the version catalog, the root build file
# (allWarningsAsErrors), gradle.properties (kotlin.native.*), the Gradle wrapper version and
# local.properties (BuildKonfig compiles DIRECTIONS_API_KEY into the iOS framework).
STAMP_FILE="shared/build/.xcode_kmp_stamp"
XCFRAMEWORK="shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework"
SOURCE_DIRS="domain/src data/src core/src shared/src shared-uitest/src"
BUILD_FILES="settings.gradle.kts build.gradle.kts gradle.properties gradle/libs.versions.toml gradle/wrapper/gradle-wrapper.properties domain/build.gradle.kts data/build.gradle.kts core/build.gradle.kts shared/build.gradle.kts shared-uitest/build.gradle.kts"
OPTIONAL_FILES="local.properties"

VARIANT_XCFRAMEWORK="shared-uitest/build/XCFrameworks/debug/TrailMetricsShared.xcframework"

INPUT_LIST="$(mktemp)"
API_DIR=""
trap 'rm -f "$INPUT_LIST" "$INPUT_LIST.sums"; [ -z "$API_DIR" ] || rm -rf "$API_DIR"' EXIT
find $SOURCE_DIRS -type f \( -name "*.kt" -o -name "*.kts" \) > "$INPUT_LIST"
for file in $BUILD_FILES; do
  if [ ! -f "$file" ]; then
    echo "error: KMP framework input $file is missing"
    exit 1
  fi
  echo "$file" >> "$INPUT_LIST"
done
for file in $OPTIONAL_FILES; do
  if [ -f "$file" ]; then
    echo "$file" >> "$INPUT_LIST"
  fi
done

# Content hash, not mtime: a touch or a branch round-trip that restores the same content
# doesn't force a Gradle run. Written to a file so a find/shasum failure stops the script.
sort -o "$INPUT_LIST" "$INPUT_LIST"
tr '\n' '\0' < "$INPUT_LIST" | xargs -0 shasum > "$INPUT_LIST.sums"
CURRENT_HASH="$(shasum < "$INPUT_LIST.sums" | awk '{print $1}')"

# --- API check of the uitest variant ---
# The variant must have production's API plus the declarations of the UI-test seam, and nothing
# else. Compared per slice: the Objective-C headers and every Swift interface of the framework.
# Each file is normalised, then compared as a sorted list of lines (the variant orders some
# declarations differently):
#   - SKIE's per-build counters (`Skie_Suspend__12__...`, `Skie__TypeDef__3__...`) become `__N__`.
#   - The `cancel` label swap (docs/epics/ios-ui-tests.md, F12): the variant gives the Swift
#     labels `cancel(cause:)` and `cancel(cause_:)` of Ktor's ByteReadChannel/ByteWriteChannel
#     (a Throwable) and coroutines' Job (a CancellationException) the other way round. Another
#     `export(...)` order did not remove it, so exactly these method lines lose their label.
#   - Variant only: the declarations whose own name contains UiTest (the Objective-C classes
#     TMSUiTest*, which hold the top-level functions too, and in the Swift interface SKIE's
#     UiTestScenario enum, its extensions and doInitKoinIosForUiTest) are left out, and their
#     names leave the `@class` forward declaration line.
#   - Blank lines are dropped (the left-out declarations leave theirs behind).
# Anything else that differs fails the build. Production must contain no UiTest name at all.
normalise_api() {
  sed -E \
    -e 's/__[0-9]+__/__N__/g' \
    -e 's/^- \(void\)cancelCause_?:\((TMSKotlinThrowable|TMSKotlinCancellationException) \* _Nullable\)cause __attribute__\(\(swift_name\("cancel\(cause_?:\)"\)\)\);$/- (void)cancelCause<label>:(\1 * _Nullable)cause __attribute__((swift_name("cancel(cause<label>:)")));/' \
    "$1" \
  | awk -v kind="$2" '
      function flush(   i) { for (i = 1; i <= n; i++) print buf[i]; n = 0 }
      kind == "h" {
        if (inblock) {
          buf[++n] = $0
          if ($0 == "@end") { if (!drop) flush(); n = 0; inblock = 0 }
          next
        }
        if ($0 ~ /^@class /) { gsub(/ TMSUiTest[A-Za-z0-9_]*,/, ""); gsub(/, TMSUiTest[A-Za-z0-9_]*;/, ";") }
        if ($0 ~ /^@(interface|protocol) / && $0 !~ /;$/) {
          buf[++n] = $0; inblock = 1; drop = ($0 ~ /^@(interface|protocol) TMS[A-Za-z0-9_]*UiTest/)
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
          drop = ($0 ~ /(func|enum|class|struct|protocol|typealias|var|let) [A-Za-z0-9_]*UiTest/ ||
            $0 ~ /^extension [A-Za-z0-9_:.]*UiTest[A-Za-z0-9_]*[ {:]/)
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
          "its UiTest declarations (< production only, > uitest variant only):"
        head -n 40 "$API_DIR/diff"
        status=1
      fi
    done
    if ! grep -q 'doInitKoinIosForUiTest' "$variant_framework/Headers/TrailMetricsShared.h"; then
      echo "error: API check: the uitest framework's $slice has no doInitKoinIosForUiTest"
      status=1
    fi
  done
  variant_slices=0
  for variant_framework in "$variant"/*/TrailMetricsShared.framework; do
    [ ! -d "$variant_framework" ] || variant_slices=$((variant_slices + 1))
  done
  if [ "$slices" -ne 2 ] || [ "$variant_slices" -ne 2 ]; then
    echo "error: API check: expected 2 slices (ios-arm64, ios-arm64-simulator) in both frameworks"
    status=1
  fi
  if [ "$status" -ne 0 ]; then
    return 1
  fi
  echo "API check: the uitest variant has production's API plus its UiTest declarations only" \
    "($slices slices)."
}

STAMP_VALUE="$VARIANT $CURRENT_HASH"
if [ -f "$STAMP_FILE" ] && [ -d "$XCFRAMEWORK" ] && [ "$(cat "$STAMP_FILE")" = "$STAMP_VALUE" ]; then
  echo "KMP shared framework ($VARIANT) is up to date, skipping Gradle build."
  exit 0
fi

echo "KMP source or framework variant changed, rebuilding shared framework ($VARIANT)..."
# Drop the stamp first and write it only after Gradle, the API check and the copy succeed
# (set -e), so a failed or interrupted build can never leave a stamp that matches a stale or
# partial framework. The framework at the debug path goes too, so Gradle always writes
# production's framework again even when the variant was copied over it.
rm -f "$STAMP_FILE"
rm -rf "$XCFRAMEWORK"
if [ "$VARIANT" = uitest ]; then
  # Production is built too: the API check compares the two.
  ./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework :shared-uitest:assembleTrailMetricsSharedDebugXCFramework
  check_variant_api "$XCFRAMEWORK" "$VARIANT_XCFRAMEWORK" || exit 1
  rm -rf "$XCFRAMEWORK"
  cp -R "$VARIANT_XCFRAMEWORK" "$XCFRAMEWORK"
else
  ./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework
fi
echo "$STAMP_VALUE" > "$STAMP_FILE"

if [ "$BUILD_PHASE" = true ]; then
  echo "error: The KMP shared framework was out of date when this Xcode build started, so this" \
    "build compiled against the old copy. It is rebuilt now: build again. The shared TrailMetrics" \
    "scheme's Build pre-action normally prevents this; check that Xcode uses that scheme and not" \
    "a per-user copy (xcuserdata) without the pre-action."
  exit 1
fi
