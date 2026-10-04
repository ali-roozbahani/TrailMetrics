#!/bin/sh
# Fixture: the top of a framework build script, cut down to its BUILD_FILES.
BUILD_FILES="gradle//libs.versions.toml"
for file in $BUILD_FILES; do
  echo "$file"
done
