#!/usr/bin/env bash
# usage:
#   scripts/b.sh --self-test   its tests
if [ "${1:-}" = "--self-test" ]; then echo "b.sh self-test ran"; exit 0; fi
echo run
