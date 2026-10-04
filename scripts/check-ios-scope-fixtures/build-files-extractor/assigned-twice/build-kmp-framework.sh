#!/bin/sh
# Fixture: the top of a framework build script, cut down to its BUILD_FILES.
BUILD_FILES="settings.gradle.kts gradle.properties shared/build.gradle.kts"
BUILD_FILES="buildSrc/build.gradle.kts"
for file in $BUILD_FILES; do
  echo "$file"
done
