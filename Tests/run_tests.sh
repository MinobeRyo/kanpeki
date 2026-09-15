#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/kanpeki-tests.XXXXXX")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 "$project_dir/Tests/make_fixtures.py" "$test_dir/fixtures"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Shared/Models.swift" "$project_dir/Shared/PracticeAnalysis.swift" "$project_dir/Shared/PresentationTimer.swift" "$project_dir/Shared/SlidePointer.swift" "$project_dir/Shared/SlideFrame.swift" "$project_dir/Mac/PPTXImporter.swift" \
  "$project_dir/Tests/CoreTests.swift" "$project_dir/Tests/SlidePointerTests.swift" "$project_dir/Tests/SlideFrameTests.swift" -o "$test_dir/core-tests"
"$test_dir/core-tests" "$test_dir/fixtures"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Shared/Models.swift" "$project_dir/Shared/PracticeAnalysis.swift" "$project_dir/Shared/PresentationTimer.swift" "$project_dir/Shared/SlidePointer.swift" "$project_dir/Shared/SlideFrame.swift" \
  "$project_dir/Tests/TimerTests.swift" -o "$test_dir/timer-tests"
"$test_dir/timer-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Shared/PresentationNotificationPolicy.swift" \
  "$project_dir/Tests/NotificationTests.swift" -o "$test_dir/notification-tests"
"$test_dir/notification-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Shared/Models.swift" "$project_dir/Shared/PracticeAnalysis.swift" "$project_dir/Shared/PresentationTimer.swift" "$project_dir/Shared/SlidePointer.swift" "$project_dir/Shared/SlideFrame.swift" \
  "$project_dir/Mac/PowerPointBridge.swift" "$project_dir/Tests/PowerPointBridgeTests.swift" -o "$test_dir/powerpoint-tests"
"$test_dir/powerpoint-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Shared/PeerApprovalState.swift" "$project_dir/Tests/PeerApprovalTests.swift" -o "$test_dir/peer-tests"
"$test_dir/peer-tests"
echo "Test artifacts: $test_dir"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Shared/PresentationTimer.swift" "$project_dir/Shared/MacPresentationStart.swift" \
  "$project_dir/Tests/MacPresentationStartTests.swift" -o "$test_dir/mac-start-tests"
"$test_dir/mac-start-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Shared/DirectPairing.swift" "$project_dir/Tests/PairingTicketTests.swift" -o "$test_dir/pairing-tests"
"$test_dir/pairing-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/experiments/AudioCapture/ios/KanpekiAudio/AudioAPI.swift" \
  "$project_dir/Tests/AudioIdentityTests.swift" -o "$test_dir/audio-identity-tests"
"$test_dir/audio-identity-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/experiments/AudioCapture/ios/KanpekiAudio/AudioAPI.swift" \
  "$project_dir/Tests/AudioReportValidationTests.swift" -o "$test_dir/audio-report-tests"
"$test_dir/audio-report-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/experiments/AudioCapture/ios/KanpekiAudio/AudioAPI.swift" \
  "$project_dir/Tests/AudioReviewChecks.swift" -o "$test_dir/audio-review-tests"
"$test_dir/audio-review-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Mac/DocumentPreview.swift" "$project_dir/Tests/MacSetupTests.swift" -o "$test_dir/mac-setup-tests"
"$test_dir/mac-setup-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$project_dir/Shared/PracticeAnalysis.swift" \
  "$project_dir/experiments/AudioCapture/ios/KanpekiAudio/AudioAPI.swift" \
  "$project_dir/iOS/AudioAnalysisEvidence.swift" \
  "$project_dir/Tests/PracticeAnalysisTests.swift" -o "$test_dir/practice-analysis-tests"
"$test_dir/practice-analysis-tests"
