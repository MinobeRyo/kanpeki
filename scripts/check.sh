#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
case "${1:-core}" in
 core) python3 Tests/test_team.py; bash Tests/run_tests.sh ;;
 mac) xcodebuild -project Kanpeki.xcodeproj -scheme KanpekiMac -configuration Debug -derivedDataPath .build/mac build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ;;
 phone) xcodebuild -project Kanpeki.xcodeproj -scheme KanpekiPhone -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/phone build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ;;
 *) echo 'Usage: check.sh core|mac|phone' >&2; exit 2 ;;
esac
