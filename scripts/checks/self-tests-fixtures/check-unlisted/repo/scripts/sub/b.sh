#!/usr/bin/env bash
# usage:
#   scripts/sub/b.sh --self-test   its tests
if [ "${1:-}" = "--self-test" ]; then echo "sub/b.sh self-test ran"; exit 0; fi
echo run
