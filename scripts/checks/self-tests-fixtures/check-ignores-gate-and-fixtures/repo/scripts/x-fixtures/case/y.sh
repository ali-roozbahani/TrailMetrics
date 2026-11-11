#!/usr/bin/env bash
# usage:
#   scripts/x-fixtures/case/y.sh --self-test   its tests
if [ "${1:-}" = "--self-test" ]; then echo "x-fixtures/case/y.sh self-test ran"; exit 0; fi
echo run
