# Task 2 report

Files: `TranscriptPolishClient.swift`, `TranscriptPolishValidator.swift`, focused client/validator tests, and `project.yml` (test-target generated Info.plist setting). Xcode project regenerated; folder-synchronised project required no tracked `.pbxproj` diff.

RED: `xcodegen generate --spec apps/macos/TSB/project.yml && CODE_SIGNING_ALLOWED=NO xcodebuild ... /tmp/tsb-polish-task2-red ... test` failed before new interfaces compiled because the baseline test target lacked an Info.plist.

GREEN: `xcodebuild CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -derivedDataPath /tmp/tsb-polish-task2-green -only-testing:TSBTests/TranscriptPolishValidatorTests -only-testing:TSBTests/TranscriptPolishClientTests test` passed: 10 tests, 0 failures. `git diff --check` passed.

Self-review: separate client, strict allowlisted DTO shapes, fixed byte/candidate/terminology limits, HTTPS-or-loopback gate, redirect delegate, single-choice response, no retries/logging/SDK/tools/streaming. Validator retains context-only rewrites as review-required and rejects immutable token changes.

Concern: this task implements only the contract boundary; the coordinator-owned deadline, persistence, delivery lease, and settings consent are intentionally left for later tasks.
