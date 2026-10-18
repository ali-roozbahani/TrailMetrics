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
#                  otherwise. Callers outside Xcode pass --variant uitest when they need the
#                  variant (CI's ios-build-ui job, the gate's smoke UI test step); every other
#                  step builds production.
#
# Variants (ADR-002, "Amendment"):
#   production  :shared's framework, what every normal Debug and Release build links.
#   uitest      The test-only variant built by :shared-uitest: the same Swift module with the
#               same API plus the UI-test seam (package dev.roozbahani.trailmetrics.uitest). It
#               is copied over the production framework's debug path, so SharedKit/Package.swift
#               stays as it is, and only after its API passed scripts/check-variant-api.sh.
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
trap 'rm -f "$INPUT_LIST" "$INPUT_LIST.sums"' EXIT
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
  scripts/check-variant-api.sh "$XCFRAMEWORK" "$VARIANT_XCFRAMEWORK" || exit 1
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
