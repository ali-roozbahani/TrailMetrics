#!/bin/sh
# Builds the debug TrailMetricsShared.xcframework that iosApp/Packages/SharedKit links, but only
# when one of its inputs changed since the last successful build. The single entry point for
# that framework outside CI: the TrailMetrics scheme's Build pre-action, the app target's
# "Build KMP Shared Framework" phase and scripts/pre-push-check.sh all call this script.
#
# Usage: scripts/build-kmp-framework.sh [--build-phase]
#   --build-phase  Called from inside the Xcode build. By then Xcode has already copied the
#                  XCFramework and compiled the Swift packages against it, so a rebuild here is
#                  too late for this build: rebuild, then fail with an error asking for another
#                  build instead of linking the stale copy. Normally the scheme pre-action has
#                  already built it (a failing pre-action fails the build) and this mode only
#                  checks the hash. It fires when the pre-action didn't run at all.
set -eu
cd "$(dirname "$0")/.."

BUILD_PHASE=false
if [ "${1:-}" = "--build-phase" ]; then
  BUILD_PHASE=true
fi

# The hash covers everything that changes the framework's content: Kotlin sources of the four
# exported modules, their build files, settings, the version catalog, the root build file
# (allWarningsAsErrors), gradle.properties (kotlin.native.*), the Gradle wrapper version and
# local.properties (BuildKonfig compiles DIRECTIONS_API_KEY into the iOS framework).
STAMP_FILE="shared/build/.xcode_kmp_stamp"
XCFRAMEWORK="shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework"
SOURCE_DIRS="domain/src data/src core/src shared/src"
BUILD_FILES="settings.gradle.kts build.gradle.kts gradle.properties gradle/libs.versions.toml gradle/wrapper/gradle-wrapper.properties domain/build.gradle.kts data/build.gradle.kts core/build.gradle.kts shared/build.gradle.kts"
OPTIONAL_FILES="local.properties"

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

if [ -f "$STAMP_FILE" ] && [ -d "$XCFRAMEWORK" ] && [ "$(cat "$STAMP_FILE")" = "$CURRENT_HASH" ]; then
  echo "KMP shared framework is up to date, skipping Gradle build."
  exit 0
fi

echo "KMP source changed, rebuilding shared framework..."
# Drop the stamp first and write it only after Gradle succeeds (set -e), so a failed or
# interrupted build can never leave a stamp that matches a stale or partial framework.
rm -f "$STAMP_FILE"
./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework
echo "$CURRENT_HASH" > "$STAMP_FILE"

if [ "$BUILD_PHASE" = true ]; then
  echo "error: The KMP shared framework was out of date when this Xcode build started, so this" \
    "build compiled against the old copy. It is rebuilt now: build again. The shared TrailMetrics" \
    "scheme's Build pre-action normally prevents this; check that Xcode uses that scheme and not" \
    "a per-user copy (xcuserdata) without the pre-action."
  exit 1
fi
