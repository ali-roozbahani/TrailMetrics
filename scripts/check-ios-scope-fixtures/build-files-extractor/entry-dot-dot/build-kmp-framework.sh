#!/bin/sh
# Fixture: the top of a framework build script, cut down to its BUILD_FILES.
BUILD_FILES="shared/../gradle.properties"
for file in $BUILD_FILES; do
  echo "$file"
done
