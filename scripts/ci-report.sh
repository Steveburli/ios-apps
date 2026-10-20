#!/bin/bash
# Used by .github/workflows/build.yml. Turns test.log and build.log into:
#   report/errors.txt         unique compiler and test errors, repo-relative paths
#   report/issues.txt         the same plus warnings
#   report/test.log, build.log  the full logs
# and writes a short summary for the run's page on GitHub.
# Usage: ci-report.sh <App> <tests outcome> <build outcome>
set -uo pipefail

app="$1"
tests="$2"
build="$3"
workspace="${GITHUB_WORKSPACE:-$PWD}/"

mkdir -p report
cp test.log build.log report/ 2>/dev/null || true

# "path:line:col: error: …" from the compiler and "path:line: error: …" from XCTest.
cat test.log build.log 2>/dev/null \
  | grep -E ':[0-9]+(:[0-9]+)?: (error|warning): ' \
  | sed "s#${workspace}##g" \
  | sort -u > report/issues.txt

grep -E ': error: ' report/issues.txt > report/errors.txt || true

# Errors without a file location (linker, package resolution, scheme problems).
cat test.log build.log 2>/dev/null \
  | grep -E '^(error|ld|xcodebuild: error|Undefined symbols|clang: error)' \
  | sed "s#${workspace}##g" \
  | sort -u >> report/errors.txt || true

errors=$(wc -l < report/errors.txt | tr -d ' ')
warnings=$(grep -c ': warning: ' report/issues.txt || true)

{
  echo "## ${app}"
  echo "Logic tests: **${tests}** · App build: **${build}** · ${errors} errors · ${warnings} warnings"
  if [ "${errors}" -gt 0 ]; then
    echo
    echo '```'
    head -80 report/errors.txt
    echo '```'
  fi
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
