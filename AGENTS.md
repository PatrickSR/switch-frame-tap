# Agent notes

## iOS SFTCore package (`ios/SFTCore`)
- Run tests: `swift test --package-path ios/SFTCore` from the repo root (no build config needed; XCTest on macOS, verified with Swift 6.4.2 / Xcode 27.2).

## iOS app (`ios/SFTap.xcodeproj`)
- Simulator build: `xcodebuild -project ios/SFTap.xcodeproj -scheme SFTap -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` (verified with Xcode 27.2; same command works with `-destination 'generic/platform=iOS'` for the device SDK).
- Replay-server self test: `python3 android-tv/tools/test_replay_server.py` (two PASS lines).
- Simulator e2e: `python3 android-tv/tools/replay_server.py logs/m83-runI/stream-first10.sft --tone --input --bind 127.0.0.1 --no-beacon` then `xcrun simctl launch <device> io.github.switchframetap.ios -autoConnectHost 127.0.0.1 -showStats YES`.
