#!/bin/sh
# Fixture: the top of a framework build script, cut down to its BUILD_FILES.
ROOT_FILES="settings.gradle.kts"
BUILD_FILES="$ROOT_FILES gradle.properties"
for file in $BUILD_FILES; do
  echo "$file"
done
