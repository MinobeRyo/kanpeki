#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/kanpeki-tests.XXXXXX")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 "$project_dir/Tests/make_fixtures.py" "$test_dir/fixtures"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Shared/Models.swift" "$project_dir/Mac/PPTXImporter.swift" \
  "$project_dir/Tests/CoreTests.swift" -o "$test_dir/core-tests"
"$test_dir/core-tests" "$test_dir/fixtures"
echo "Test artifacts: $test_dir"
