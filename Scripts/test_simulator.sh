#!/bin/bash
set -euo pipefail
device=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for runtime,devices in d["devices"].items() if ".iOS-" in runtime for x in devices if x["name"].startswith("iPhone") and x.get("isAvailable",True)))')
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcodebuild -project YouTubeDownload.xcodeproj -scheme YouTubeDownload -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath build-simulator CODE_SIGNING_ALLOWED=NO build-for-testing | tee simulator-build.log
xcrun simctl install "$device" build-simulator/Build/Products/Debug-iphonesimulator/YouTubeDownload.app
xcrun simctl privacy "$device" grant photos-add com.starjack1211.YouTubeDownload
xcodebuild -project YouTubeDownload.xcodeproj -scheme YouTubeDownload -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath build-simulator \
  -parallel-testing-enabled NO -resultBundlePath SimulatorTests.xcresult \
  CODE_SIGNING_ALLOWED=NO test-without-building | tee simulator-tests.log
