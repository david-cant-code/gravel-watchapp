#!/bin/sh
# Compiler settings in the caller's environment must not reach the watch build.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build-test
CC=false CFLAGS=-DLEAKED_FROM_ENV LDFLAGS=-DLEAKED_FROM_ENV tools/build.sh > build-test/build_env_test.log 2>&1 \
  || { cat build-test/build_env_test.log; echo "build failed with CC/CFLAGS set" >&2; exit 1; }
[ -d build/c4che ] || { echo "no waf configuration in build/c4che to check" >&2; exit 1; }
if grep -rq LEAKED_FROM_ENV build/c4che; then
  echo "CFLAGS/LDFLAGS from the environment reached the build configuration" >&2
  exit 1
fi
echo "build environment test passed"
