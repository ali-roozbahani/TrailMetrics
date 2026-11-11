#!/usr/bin/env bash
# usage:
#   scripts/a.sh --self-test   its tests
if [ "${1:-}" = "--self-test" ]; then echo "a.sh self-test ran"; exit 0; fi
echo run
