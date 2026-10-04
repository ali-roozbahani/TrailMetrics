#!/bin/sh
# Fixture: the top of a framework build script, cut down to its BUILD_FILES.
BUILD_FILES="$(cat build-files.txt)"
for file in $BUILD_FILES; do
  echo "$file"
done
