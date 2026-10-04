#!/bin/sh
# Fixture: the top of a framework build script, cut down to its BUILD_FILES.
BUILD_FILES="settings.gradle.kts */build.gradle.kts"
for file in $BUILD_FILES; do
  echo "$file"
done
